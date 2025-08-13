#!/usr/bin/env python3
"""
Script to extract star information from HYG database CSV file and store them in SQLite.

This script reads a HYG database CSV file, extracts all columns except the excluded ones
(ra, dec, dist, pmra, pmdec, rv, vx, vy, vz, rarad, decrad, pmrarad, pmdecrad),
and stores them in a SQLite database table called 'stars_info'.
"""

import argparse
import csv
import sqlite3
import sys
import os
from pathlib import Path


def parse_arguments():
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(
        description="Extract star information from HYG database CSV and store in SQLite"
    )
    
    parser.add_argument(
        "csv_file",
        type=str,
        help="Path to the HYG database CSV file"
    )
    
    parser.add_argument(
        "--sqlite-file",
        type=str,
        default="stars_info.sqlite3",
        help="Path to output SQLite file (default: stars_info.sqlite3)"
    )
    
    return parser.parse_args()


def validate_csv_file(csv_file):
    """Validate that the CSV file exists and has the required columns."""
    if not os.path.exists(csv_file):
        print(f"Error: CSV file '{csv_file}' does not exist.")
        sys.exit(1)
    
    # Check if the file has the id column (required as key)
    required_columns = {"id"}
    
    try:
        with open(csv_file, 'r', newline='', encoding='utf-8') as file:
            reader = csv.DictReader(file)
            if not required_columns.issubset(set(reader.fieldnames)):
                missing = required_columns - set(reader.fieldnames)
                print(f"Error: CSV file is missing required columns: {missing}")
                sys.exit(1)
            return reader.fieldnames
    except Exception as e:
        print(f"Error reading CSV file: {e}")
        sys.exit(1)


def get_included_columns(all_columns):
    """Get the list of columns to include (excluding specified ones)."""
    excluded_columns = {
        "ra", "dec", "dist", "pmra", "pmdec", "rv", 
        "vx", "vy", "vz", "rarad", "decrad", "pmrarad", "pmdecrad",
        "x", "y", "z"
    }
    
    included_columns = [col for col in all_columns if col not in excluded_columns]
    
    print(f"Excluding columns: {sorted(excluded_columns)}")
    print(f"Including columns: {included_columns}")
    
    return included_columns


def read_stars(csv_file, included_columns):
    """Read stars from CSV file with only the included columns."""
    stars = []
    
    try:
        with open(csv_file, 'r', newline='', encoding='utf-8') as file:
            reader = csv.DictReader(file)
            
            for row_num, row in enumerate(reader, start=2):  # Start at 2 since header is line 1
                try:
                    # Extract only the included fields
                    star = {}
                    for col in included_columns:
                        value = row.get(col, '')
                        
                        # Convert specific columns to appropriate types
                        if col == 'id':
                            star[col] = int(value) if value else None
                        elif col in ['hip', 'hd', 'hr', 'comp', 'comp_primary', 'flam']:
                            star[col] = int(value) if value and value.strip() else None
                        elif col in ['mag', 'absmag', 'ci', 'lum', 'var_min', 'var_max']:
                            star[col] = float(value) if value and value.strip() else None
                        else:
                            # String fields (including gl, bf, proper, spect, bayer, con, var, base, etc.): keep as string, convert empty to None
                            star[col] = value if value and value.strip() else None
                    
                    # Skip rows without an ID
                    if star['id'] is None:
                        print(f"Warning: Skipping row {row_num} - no ID")
                        continue
                        
                    stars.append(star)
                    
                except (ValueError, TypeError) as e:
                    # Skip rows with invalid data
                    print(f"Warning: Skipping row {row_num} with invalid data: {e}")
                    continue
    
    except Exception as e:
        print(f"Error reading CSV file: {e}")
        sys.exit(1)
    
    return stars


def create_sqlite_database(sqlite_file, stars, included_columns):
    """Create SQLite database and insert the star information."""
    table_name = "stars_info"
    
    try:
        # Create database connection
        conn = sqlite3.connect(sqlite_file)
        cursor = conn.cursor()
        
        # Drop existing table if it exists
        cursor.execute(f"DROP TABLE IF EXISTS {table_name}")
        
        # Create column definitions for CREATE TABLE
        column_definitions = []
        for col in included_columns:
            if col == 'id':
                column_definitions.append(f"{col} INTEGER PRIMARY KEY")
            elif col in ['hip', 'hd', 'hr', 'comp', 'comp_primary', 'flam']:
                column_definitions.append(f"{col} INTEGER")
            elif col in ['mag', 'absmag', 'ci', 'lum', 'var_min', 'var_max']:
                column_definitions.append(f"{col} REAL")
            else:
                column_definitions.append(f"{col} TEXT")
        
        # Create new table
        create_table_sql = f"""
        CREATE TABLE {table_name} (
            {', '.join(column_definitions)}
        )
        """
        cursor.execute(create_table_sql)
        
        # Insert data
        placeholders = ', '.join(['?' for _ in included_columns])
        insert_sql = f"""
        INSERT OR REPLACE INTO {table_name} ({', '.join(included_columns)})
        VALUES ({placeholders})
        """
        
        for star in stars:
            values = [star.get(col) for col in included_columns]
            cursor.execute(insert_sql, values)
        
        # Commit changes and close connection
        conn.commit()
        conn.close()
        
        print(f"Successfully created table '{table_name}' with {len(stars)} stars")
        print(f"SQLite database saved to: {sqlite_file}")
        
    except Exception as e:
        print(f"Error creating SQLite database: {e}")
        sys.exit(1)


def main():
    """Main function."""
    args = parse_arguments()
    
    print(f"Processing HYG database: {args.csv_file}")
    print(f"Output SQLite file: {args.sqlite_file}")
    
    # Validate input file and get column names
    all_columns = validate_csv_file(args.csv_file)
    
    # Determine which columns to include
    included_columns = get_included_columns(all_columns)
    
    # Read stars
    print("Reading star information...")
    stars = read_stars(args.csv_file, included_columns)
    
    if not stars:
        print("Error: No valid star data found in CSV file.")
        sys.exit(1)
    
    print(f"Found {len(stars)} stars with valid data")
    
    # Create SQLite database
    print("Creating SQLite database...")
    create_sqlite_database(args.sqlite_file, stars, included_columns)
    
    print("Processing complete!")


if __name__ == "__main__":
    main()
