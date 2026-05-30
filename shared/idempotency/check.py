processed_jobs = set()


def already_processed(job_id):

    if job_id in processed_jobs:
        return True

    processed_jobs.add(job_id)

    return False
