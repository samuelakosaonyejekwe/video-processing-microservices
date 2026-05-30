from app.database.connection import get_db_connection


def create_users_table():

    connection = get_db_connection()

    cursor = connection.cursor()

    cursor.execute("""
        CREATE TABLE IF NOT EXISTS users (
            id SERIAL PRIMARY KEY,
            username VARCHAR(100),
            email VARCHAR(255) UNIQUE,
            password VARCHAR(255)
        );
        """)

    connection.commit()

    cursor.close()

    connection.close()


if __name__ == "__main__":

    create_users_table()

    print("Users table created successfully.")
