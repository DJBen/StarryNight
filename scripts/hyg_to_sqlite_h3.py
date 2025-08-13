#!/usr/bin/env python3
"""
Script to extract stars from HYG database CSV file and store them with H3 geospatial indexing.

This script reads a HYG database CSV file, skips the first N brightest stars,
then creates up to three tables:
- stars_h3_0: Next lvl_0_count stars with H3 resolution level 0 hashes
- stars_h3_1: Next lvl_1_count stars with H3 resolution level 1 hashes
- stars_h3_2: All remaining stars with H3 resolution level 2 hashes (optional)

Stars are sorted by magnitude (ascending) before processing.
"""

import argparse
import csv
import sqlite3
import sys
import os
import h3
import math
from pathlib import Path


def extract_spectral_class(spect):
    """Extract spectral class according to the specified rule."""
    if not spect or not spect.strip():
        return None
    
    spect = spect.strip()
    
    # Handle "sd" prefix (subdwarf) - remove "sd" and get first uppercase letter
    if spect.lower().startswith('sd') and len(spect) > 2:
        remaining = spect[2:]
        for char in remaining:
            if char.isupper():
                return char
    # Handle "d" prefix (dwarf) - remove "d" and get first uppercase letter  
    elif spect.lower().startswith('d') and len(spect) > 1:
        remaining = spect[1:]
        for char in remaining:
            if char.isupper():
                return char
    # Normal case - get first uppercase letter
    else:
        for char in spect:
            if char.isupper():
                return char
    
    return None


def parse_arguments():
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(
        description="Extract stars from HYG database CSV and store with H3 geospatial indexing"
    )
    
    parser.add_argument(
        "csv_file",
        type=str,
        help="Path to the HYG database CSV file"
    )
    
    parser.add_argument(
        "--sqlite-file",
        type=str,
        default="stars_h3.sqlite3",
        help="Path to output SQLite file (default: stars_h3.sqlite3)"
    )
    
    parser.add_argument(
        "--skip",
        type=int,
        default=0,
        help="Number of brightest stars to skip (default: 0)"
    )
    
    parser.add_argument(
        "--lvl-0-count",
        type=int,
        default=100,
        help="Number of stars to process for H3 level 0 (default: 100)"
    )
    
    parser.add_argument(
        "--lvl-1-count",
        type=int,
        default=100,
        help="Number of stars to process for H3 level 1 (default: 100)"
    )
    
    parser.add_argument(
        "--include-rest",
        action="store_true",
        help="Process all remaining stars with H3 level 2"
    )
    
    return parser.parse_args()


def validate_csv_file(csv_file):
    """Validate that the CSV file exists and has the required columns."""
    if not os.path.exists(csv_file):
        print(f"Error: CSV file '{csv_file}' does not exist.")
        sys.exit(1)
    
    # Check if the file has the required columns
    required_columns = {"id", "mag", "x", "y", "z", "spect"}
    
    try:
        with open(csv_file, 'r', newline='', encoding='utf-8') as file:
            reader = csv.DictReader(file)
            if not required_columns.issubset(set(reader.fieldnames)):
                missing = required_columns - set(reader.fieldnames)
                print(f"Error: CSV file is missing required columns: {missing}")
                sys.exit(1)
    except Exception as e:
        print(f"Error reading CSV file: {e}")
        sys.exit(1)


def cartesian_to_lat_lon(x, y, z):
    """Convert Cartesian coordinates to latitude and longitude."""
    # Normalize the vector (in case it's not already unit length)
    magnitude = math.sqrt(x*x + y*y + z*z)
    if magnitude == 0:
        return None, None
    
    x_norm = x / magnitude
    y_norm = y / magnitude
    z_norm = z / magnitude
    
    # Convert to spherical coordinates
    # Latitude (declination): arcsin(z)
    lat = math.asin(z_norm) * 180 / math.pi
    
    # Longitude (right ascension): atan2(y, x)
    lon = math.atan2(y_norm, x_norm) * 180 / math.pi
    
    return lat, lon


def read_and_sort_stars(csv_file):
    """Read all stars from CSV and sort by magnitude."""
    stars = []
    
    try:
        with open(csv_file, 'r', newline='', encoding='utf-8') as file:
            reader = csv.DictReader(file)
            
            for row in reader:
                try:
                    # Extract required fields and convert to appropriate types
                    star = {
                        'id': int(row['id']) if row['id'] else None,
                        'mag': float(row['mag']) if row['mag'] else float('inf'),
                        'x': float(row['x']) if row['x'] else None,
                        'y': float(row['y']) if row['y'] else None,
                        'z': float(row['z']) if row['z'] else None,
                        'spect_class': extract_spectral_class(row.get('spect', ''))
                    }
                    
                    # Skip stars with missing coordinate data
                    if any(coord is None for coord in [star['x'], star['y'], star['z']]):
                        continue
                        
                    stars.append(star)
                except (ValueError, TypeError) as e:
                    # Skip rows with invalid data
                    print(f"Warning: Skipping row with invalid data: {e}")
                    continue
    
    except Exception as e:
        print(f"Error reading CSV file: {e}")
        sys.exit(1)
    
    # Sort by magnitude (ascending - brighter stars have lower magnitude)
    stars.sort(key=lambda x: x['mag'])
    
    return stars


def process_stars_with_h3(stars, start_index, count, h3_resolution):
    """Process a subset of stars and add H3 hashes."""
    processed_stars = []
    end_index = min(start_index + count, len(stars))
    
    for i in range(start_index, end_index):
        star = stars[i].copy()
        
        # Convert Cartesian coordinates to lat/lon
        lat, lon = cartesian_to_lat_lon(star['x'], star['y'], star['z'])
        
        if lat is not None and lon is not None:
            # Generate H3 hash
            try:
                h3_hash = h3.latlng_to_cell(lat, lon, h3_resolution)
                star[f'h3_{h3_resolution}'] = h3_hash
                processed_stars.append(star)
            except Exception as e:
                print(f"Warning: Could not generate H3 hash for star {star['id']}: {e}")
                continue
        else:
            print(f"Warning: Could not convert coordinates for star {star['id']}")
            continue
    
    return processed_stars


def create_sqlite_database(sqlite_file, stars_h3_0, stars_h3_1, stars_h3_2=None):
    """Create SQLite database and insert the stars with H3 hashes."""
    try:
        # Create database connection
        conn = sqlite3.connect(sqlite_file)
        cursor = conn.cursor()
        
        # Create stars_h3_0 table
        cursor.execute("DROP TABLE IF EXISTS stars_h3_0")
        create_table_h3_0_sql = """
        CREATE TABLE stars_h3_0 (
            id INTEGER,
            mag REAL,
            x REAL,
            y REAL,
            z REAL,
            spect_class TEXT,
            h3_0 TEXT
        )
        """
        cursor.execute(create_table_h3_0_sql)
        
        # Insert H3 level 0 data
        insert_h3_0_sql = """
        INSERT INTO stars_h3_0 (id, mag, x, y, z, spect_class, h3_0)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        """
        
        for star in stars_h3_0:
            cursor.execute(insert_h3_0_sql, (
                star['id'],
                star['mag'],
                star['x'],
                star['y'],
                star['z'],
                star['spect_class'],
                star['h3_0']
            ))
        
        # Create indices for stars_h3_0
        cursor.execute("CREATE INDEX idx_stars_h3_0_h3_0 ON stars_h3_0(h3_0)")
        cursor.execute("CREATE INDEX idx_stars_h3_0_mag ON stars_h3_0(mag ASC)")
        
        # Create stars_h3_1 table
        cursor.execute("DROP TABLE IF EXISTS stars_h3_1")
        create_table_h3_1_sql = """
        CREATE TABLE stars_h3_1 (
            id INTEGER,
            mag REAL,
            x REAL,
            y REAL,
            z REAL,
            spect_class TEXT,
            h3_1 TEXT
        )
        """
        cursor.execute(create_table_h3_1_sql)
        
        # Insert H3 level 1 data
        insert_h3_1_sql = """
        INSERT INTO stars_h3_1 (id, mag, x, y, z, spect_class, h3_1)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        """
        
        for star in stars_h3_1:
            cursor.execute(insert_h3_1_sql, (
                star['id'],
                star['mag'],
                star['x'],
                star['y'],
                star['z'],
                star['spect_class'],
                star['h3_1']
            ))
        
        # Create indices for stars_h3_1
        cursor.execute("CREATE INDEX idx_stars_h3_1_h3_1 ON stars_h3_1(h3_1)")
        cursor.execute("CREATE INDEX idx_stars_h3_1_mag ON stars_h3_1(mag ASC)")
        
        # Create stars_h3_2 table if we have level 2 data
        if stars_h3_2:
            cursor.execute("DROP TABLE IF EXISTS stars_h3_2")
            create_table_h3_2_sql = """
            CREATE TABLE stars_h3_2 (
                id INTEGER,
                mag REAL,
                x REAL,
                y REAL,
                z REAL,
                spect_class TEXT,
                h3_2 TEXT
            )
            """
            cursor.execute(create_table_h3_2_sql)
            
            # Insert H3 level 2 data
            insert_h3_2_sql = """
            INSERT INTO stars_h3_2 (id, mag, x, y, z, spect_class, h3_2)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """
            
            for star in stars_h3_2:
                cursor.execute(insert_h3_2_sql, (
                    star['id'],
                    star['mag'],
                    star['x'],
                    star['y'],
                    star['z'],
                    star['spect_class'],
                    star['h3_2']
                ))
            
            # Create indices for stars_h3_2
            cursor.execute("CREATE INDEX idx_stars_h3_2_h3_2 ON stars_h3_2(h3_2)")
            cursor.execute("CREATE INDEX idx_stars_h3_2_mag ON stars_h3_2(mag ASC)")
        
        # Commit changes and close connection
        conn.commit()
        conn.close()
        
        print(f"Successfully created 'stars_h3_0' table with {len(stars_h3_0)} stars")
        print(f"Successfully created 'stars_h3_1' table with {len(stars_h3_1)} stars")
        if stars_h3_2:
            print(f"Successfully created 'stars_h3_2' table with {len(stars_h3_2)} stars")
        print(f"SQLite database saved to: {sqlite_file}")
        
    except Exception as e:
        print(f"Error creating SQLite database: {e}")
        sys.exit(1)


def main():
    """Main function."""
    args = parse_arguments()
    
    print(f"Processing HYG database: {args.csv_file}")
    print(f"Skipping first {args.skip} brightest stars")
    print(f"Processing {args.lvl_0_count} stars for H3 level 0")
    print(f"Processing {args.lvl_1_count} stars for H3 level 1")
    if args.include_rest:
        print("Processing all remaining stars for H3 level 2")
    print(f"Output SQLite file: {args.sqlite_file}")
    
    # Validate input file
    validate_csv_file(args.csv_file)
    
    # Read and sort all stars
    print("Reading and sorting stars by magnitude...")
    all_stars = read_and_sort_stars(args.csv_file)
    
    if not all_stars:
        print("Error: No valid star data found in CSV file.")
        sys.exit(1)
    
    total_stars = len(all_stars)
    print(f"Found {total_stars} valid stars")
    
    # Check if we have enough stars for the requested processing
    stars_needed = args.skip + args.lvl_0_count + args.lvl_1_count
    if total_stars < stars_needed:
        print(f"Warning: Only {total_stars} stars available, but {stars_needed} requested")
        print("Will process as many stars as available")
    
    # Process H3 level 0 stars
    print(f"Processing H3 level 0 stars (starting from index {args.skip})...")
    stars_h3_0 = process_stars_with_h3(all_stars, args.skip, args.lvl_0_count, 0)
    
    # Process H3 level 1 stars
    lvl_1_start = args.skip + args.lvl_0_count
    print(f"Processing H3 level 1 stars (starting from index {lvl_1_start})...")
    stars_h3_1 = process_stars_with_h3(all_stars, lvl_1_start, args.lvl_1_count, 1)
    
    # Process H3 level 2 stars (all remaining) if requested
    stars_h3_2 = None
    if args.include_rest:
        lvl_2_start = args.skip + args.lvl_0_count + args.lvl_1_count
        remaining_count = total_stars - lvl_2_start
        if remaining_count > 0:
            print(f"Processing H3 level 2 stars (starting from index {lvl_2_start}, {remaining_count} stars)...")
            stars_h3_2 = process_stars_with_h3(all_stars, lvl_2_start, remaining_count, 2)
        else:
            print("No remaining stars to process for H3 level 2")
    
    if not stars_h3_0 and not stars_h3_1 and not stars_h3_2:
        print("Error: No stars could be processed with H3 hashing.")
        sys.exit(1)
    
    print(f"Successfully processed {len(stars_h3_0)} stars for H3 level 0")
    print(f"Successfully processed {len(stars_h3_1)} stars for H3 level 1")
    if stars_h3_2:
        print(f"Successfully processed {len(stars_h3_2)} stars for H3 level 2")
    
    if stars_h3_0:
        print(f"H3 level 0 magnitude range: {stars_h3_0[0]['mag']:.2f} to {stars_h3_0[-1]['mag']:.2f}")
    if stars_h3_1:
        print(f"H3 level 1 magnitude range: {stars_h3_1[0]['mag']:.2f} to {stars_h3_1[-1]['mag']:.2f}")
    if stars_h3_2:
        print(f"H3 level 2 magnitude range: {stars_h3_2[0]['mag']:.2f} to {stars_h3_2[-1]['mag']:.2f}")
    
    # Create SQLite database
    print("Creating SQLite database...")
    create_sqlite_database(args.sqlite_file, stars_h3_0, stars_h3_1, stars_h3_2)
    
    print("Processing complete!")


if __name__ == "__main__":
    main()
