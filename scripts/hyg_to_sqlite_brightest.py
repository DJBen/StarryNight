#!/usr/bin/env python3
"""
Script to extract the brightest N stars from HYG database CSV file and store them in SQLite.

This script reads a HYG database CSV file, extracts the specified columns (id, mag, x, y, z),
sorts by magnitude (ascending), and stores the brightest N stars in a SQLite database.
"""

import argparse
import csv
import sqlite3
import sys
import os
import h3
import math


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


def parse_arguments():
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(
        description="Extract brightest N stars from HYG database CSV and store in SQLite"
    )
    
    parser.add_argument(
        "csv_file",
        type=str,
        help="Path to the HYG database CSV file"
    )
    
    parser.add_argument(
        "brightest_n",
        type=int,
        default=300,
        nargs='?',
        help="Number of brightest stars to extract (default: 300)"
    )
    
    parser.add_argument(
        "--sqlite-file",
        type=str,
        default="stars_brightest.sqlite3",
        help="Path to output SQLite file (default: stars_brightest.sqlite3)"
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


def read_and_sort_stars(csv_file, brightest_n):
    """Read stars from CSV, sort by magnitude, and return the brightest N."""
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
                    
                    # Convert Cartesian coordinates to lat/lon and generate H3 hash
                    lat, lon = cartesian_to_lat_lon(star['x'], star['y'], star['z'])
                    if lat is not None and lon is not None:
                        try:
                            star['h3_0'] = h3.latlng_to_cell(lat, lon, 0)
                        except Exception as e:
                            print(f"Warning: Could not generate H3 hash for star {star['id']}: {e}")
                            continue
                    else:
                        print(f"Warning: Could not convert coordinates for star {star['id']}")
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
    
    # Return the brightest N stars
    return stars[:brightest_n]


def create_sqlite_database(sqlite_file, brightest_stars, brightest_n):
    """Create SQLite database and insert the brightest stars."""
    table_name = f"stars_brightest_{brightest_n}"
    
    try:
        # Create database connection
        conn = sqlite3.connect(sqlite_file)
        cursor = conn.cursor()
        
        # Drop existing table if it exists
        cursor.execute(f"DROP TABLE IF EXISTS {table_name}")
        
        # Create new table
        create_table_sql = f"""
        CREATE TABLE {table_name} (
            id INTEGER,
            mag REAL,
            x REAL,
            y REAL,
            z REAL,
            spect_class TEXT,
            h3_0 TEXT
        )
        """
        cursor.execute(create_table_sql)
        
        # Insert data
        insert_sql = f"""
        INSERT INTO {table_name} (id, mag, x, y, z, spect_class, h3_0)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        """
        
        for star in brightest_stars:
            cursor.execute(insert_sql, (
                star['id'],
                star['mag'],
                star['x'],
                star['y'],
                star['z'],
                star['spect_class'],
                star['h3_0']
            ))
        
        # Create index on magnitude for faster queries
        cursor.execute(f"CREATE INDEX idx_{table_name}_mag ON {table_name}(mag)")
        
        # Create index on H3 hash for faster geospatial queries
        cursor.execute(f"CREATE INDEX idx_{table_name}_h3_0 ON {table_name}(h3_0)")
        
        # Commit changes and close connection
        conn.commit()
        conn.close()
        
        print(f"Successfully created table '{table_name}' with {len(brightest_stars)} stars")
        print(f"SQLite database saved to: {sqlite_file}")
        
    except Exception as e:
        print(f"Error creating SQLite database: {e}")
        sys.exit(1)


def main():
    """Main function."""
    args = parse_arguments()
    
    print(f"Processing HYG database: {args.csv_file}")
    print(f"Extracting {args.brightest_n} brightest stars")
    print(f"Output SQLite file: {args.sqlite_file}")
    
    # Validate input file
    validate_csv_file(args.csv_file)
    
    # Read and sort stars
    print("Reading and sorting stars by magnitude...")
    brightest_stars = read_and_sort_stars(args.csv_file, args.brightest_n)
    
    if not brightest_stars:
        print("Error: No valid star data found in CSV file.")
        sys.exit(1)
    
    print(f"Found {len(brightest_stars)} brightest stars")
    print(f"Magnitude range: {brightest_stars[0]['mag']:.2f} to {brightest_stars[-1]['mag']:.2f}")
    
    # Create SQLite database
    print("Creating SQLite database...")
    create_sqlite_database(args.sqlite_file, brightest_stars, args.brightest_n)
    
    print("Processing complete!")


if __name__ == "__main__":
    main()