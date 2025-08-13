#!/usr/bin/env python3
"""
SQLite Schema Inspector

This script connects to an SQLite database and prints all schema information
including tables, indexes, views, and triggers.

Usage:
    python sqlite_schema.py <path_to_database>
"""

import sqlite3
import sys
import os
from typing import List, Tuple


def print_separator(title: str, char: str = "=") -> None:
    """Print a formatted separator with title."""
    width = 80
    print(f"\n{char * width}")
    print(f" {title} ".center(width, char))
    print(f"{char * width}")


def get_tables(cursor: sqlite3.Cursor) -> List[str]:
    """Get all table names from the database."""
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;")
    return [row[0] for row in cursor.fetchall()]


def get_table_schema(cursor: sqlite3.Cursor, table_name: str) -> str:
    """Get the CREATE statement for a table."""
    cursor.execute("SELECT sql FROM sqlite_master WHERE type='table' AND name=?;", (table_name,))
    result = cursor.fetchone()
    return result[0] if result else ""


def get_table_info(cursor: sqlite3.Cursor, table_name: str) -> List[Tuple]:
    """Get detailed column information for a table."""
    cursor.execute(f"PRAGMA table_info({table_name});")
    return cursor.fetchall()


def get_indexes(cursor: sqlite3.Cursor) -> List[Tuple]:
    """Get all indexes from the database."""
    cursor.execute("SELECT name, tbl_name, sql FROM sqlite_master WHERE type='index' AND sql IS NOT NULL ORDER BY name;")
    return cursor.fetchall()


def get_views(cursor: sqlite3.Cursor) -> List[Tuple]:
    """Get all views from the database."""
    cursor.execute("SELECT name, sql FROM sqlite_master WHERE type='view' ORDER BY name;")
    return cursor.fetchall()


def get_triggers(cursor: sqlite3.Cursor) -> List[Tuple]:
    """Get all triggers from the database."""
    cursor.execute("SELECT name, tbl_name, sql FROM sqlite_master WHERE type='trigger' ORDER BY name;")
    return cursor.fetchall()


def print_database_info(cursor: sqlite3.Cursor, db_path: str) -> None:
    """Print general database information."""
    print_separator("DATABASE INFORMATION")
    print(f"Database Path: {db_path}")
    print(f"Database Size: {os.path.getsize(db_path)} bytes")
    
    # Get SQLite version
    cursor.execute("SELECT sqlite_version();")
    version = cursor.fetchone()[0]
    print(f"SQLite Version: {version}")
    
    # Get page count and page size
    cursor.execute("PRAGMA page_count;")
    page_count = cursor.fetchone()[0]
    cursor.execute("PRAGMA page_size;")
    page_size = cursor.fetchone()[0]
    print(f"Pages: {page_count} (Page size: {page_size} bytes)")


def print_tables_schema(cursor: sqlite3.Cursor) -> None:
    """Print all tables and their schemas."""
    tables = get_tables(cursor)
    
    if not tables:
        print("\nNo tables found in the database.")
        return
    
    print_separator("TABLES")
    print(f"Found {len(tables)} table(s):")
    for table in tables:
        print(f"  - {table}")
    
    for table in tables:
        print_separator(f"TABLE: {table}", "-")
        
        # Print CREATE statement
        schema = get_table_schema(cursor, table)
        if schema:
            print("CREATE Statement:")
            print(schema)


def print_indexes(cursor: sqlite3.Cursor) -> None:
    """Print all indexes."""
    indexes = get_indexes(cursor)
    
    if not indexes:
        print("\nNo indexes found in the database.")
        return
    
    print_separator("INDEXES")
    print(f"Found {len(indexes)} index(es):")
    
    for name, table, sql in indexes:
        print(f"\nIndex: {name} (Table: {table})")
        if sql:
            print(f"SQL: {sql}")


def print_views(cursor: sqlite3.Cursor) -> None:
    """Print all views."""
    views = get_views(cursor)
    
    if not views:
        print("\nNo views found in the database.")
        return
    
    print_separator("VIEWS")
    print(f"Found {len(views)} view(s):")
    
    for name, sql in views:
        print(f"\nView: {name}")
        if sql:
            print(f"SQL: {sql}")


def print_triggers(cursor: sqlite3.Cursor) -> None:
    """Print all triggers."""
    triggers = get_triggers(cursor)
    
    if not triggers:
        print("\nNo triggers found in the database.")
        return
    
    print_separator("TRIGGERS")
    print(f"Found {len(triggers)} trigger(s):")
    
    for name, table, sql in triggers:
        print(f"\nTrigger: {name} (Table: {table})")
        if sql:
            print(f"SQL: {sql}")


def inspect_database(db_path: str) -> None:
    """Main function to inspect and print database schema."""
    if not os.path.exists(db_path):
        print(f"Error: Database file '{db_path}' does not exist.")
        sys.exit(1)
    
    try:
        # Connect to database
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()
        
        # Print all schema information
        print_database_info(cursor, db_path)
        print_tables_schema(cursor)
        print_indexes(cursor)
        print_views(cursor)
        print_triggers(cursor)
        
        print_separator("SCHEMA INSPECTION COMPLETE")
        
    except sqlite3.Error as e:
        print(f"SQLite error: {e}")
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)
    finally:
        if conn:
            conn.close()


def main():
    """Main entry point."""
    if len(sys.argv) != 2:
        print("Usage: python sqlite_schema.py <path_to_database>")
        print("\nExample:")
        print("  python sqlite_schema.py stars.sqlite3")
        print("  python sqlite_schema.py /path/to/database.db")
        sys.exit(1)
    
    db_path = sys.argv[1]
    inspect_database(db_path)


if __name__ == "__main__":
    main()
