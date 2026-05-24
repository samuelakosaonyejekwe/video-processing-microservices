from app.queue.consumer import start_consumer


def run_worker():

    print("Starting conversion worker...")

    start_consumer()


if __name__ == "__main__":

    run_worker()