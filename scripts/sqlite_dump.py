import sqlite3
import io
import os
import argparse
import sys

def export_sqlite_to_sql_dump(database_path, output_sql_path):
    """
    Exports the entire content (schema and data) of a SQLite database
    to a SQL dump file.

    Args:
        database_path (str): The path to the SQLite database file.
        output_sql_path (str): The path where the SQL dump file will be saved.
    """
    try:
        conn = sqlite3.connect(database_path)
        
        # Use io.open for writing with specific encoding if needed
        # (though default 'utf-8' is usually fine)
        with io.open(output_sql_path, 'w', encoding='utf-8') as f:
            for line in conn.iterdump():
                f.write(f'{line}\n')
        
        print(f"Successfully exported '{database_path}' to '{output_sql_path}'")
        
    except sqlite3.Error as e:
        print(f"Error exporting database: {e}")
    finally:
        if conn:
            conn.close()

def import_sql_dump_to_sqlite(sql_dump_path, new_database_path):
    """
    Imports a SQL dump file to create a new, identical SQLite database.

    Args:
        sql_dump_path (str): The path to the SQL dump file.
        new_database_path (str): The path for the new SQLite database file.
    """
    try:
        # If the new database file exists, it will be overwritten.
        # Consider adding a check or prompt if this is undesirable.
        if os.path.exists(new_database_path):
            print(f"Warning: '{new_database_path}' already exists and will be overwritten.")
            os.remove(new_database_path)

        conn = sqlite3.connect(new_database_path)
        cursor = conn.cursor()

        with io.open(sql_dump_path, 'r', encoding='utf-8') as f:
            sql_script = f.read()
            cursor.executescript(sql_script)
        
        conn.commit()
        print(f"Successfully imported '{sql_dump_path}' to create '{new_database_path}'")

    except sqlite3.Error as e:
        print(f"Error importing SQL dump: {e}")
    finally:
        if conn:
            conn.close()

def main():
    """
    Main function to handle command-line arguments and execute the appropriate operation.
    """
    parser = argparse.ArgumentParser(
        description="Export SQLite databases to SQL dumps or import SQL dumps to create SQLite databases.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  Export SQLite database to SQL dump:
    python sqlite_dump.py export database.sqlite dump.sql
  
  Import SQL dump to create SQLite database:
    python sqlite_dump.py import dump.sql new_database.sqlite
        """
    )
    
    subparsers = parser.add_subparsers(dest='command', help='Available commands')
    
    # Export command
    export_parser = subparsers.add_parser('export', help='Export SQLite database to SQL dump file')
    export_parser.add_argument('database_path', help='Path to the SQLite database file')
    export_parser.add_argument('output_sql_path', help='Path where the SQL dump file will be saved')
    
    # Import command
    import_parser = subparsers.add_parser('import', help='Import SQL dump file to create SQLite database')
    import_parser.add_argument('sql_dump_path', help='Path to the SQL dump file')
    import_parser.add_argument('new_database_path', help='Path for the new SQLite database file')
    
    args = parser.parse_args()
    
    if args.command == 'export':
        if not os.path.exists(args.database_path):
            print(f"Error: Database file '{args.database_path}' does not exist.")
            sys.exit(1)
        export_sqlite_to_sql_dump(args.database_path, args.output_sql_path)
    elif args.command == 'import':
        if not os.path.exists(args.sql_dump_path):
            print(f"Error: SQL dump file '{args.sql_dump_path}' does not exist.")
            sys.exit(1)
        import_sql_dump_to_sqlite(args.sql_dump_path, args.new_database_path)
    else:
        parser.print_help()
        sys.exit(1)

if __name__ == "__main__":
    main()
