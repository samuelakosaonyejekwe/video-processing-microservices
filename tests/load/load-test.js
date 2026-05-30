import http from 'k6/http';

import { sleep } from 'k6';


export const options = {

    vus: Number(__ENV.LOAD_TEST_VUS),

    duration: __ENV.LOAD_TEST_DURATION,
};


export default function () {

    http.get(
        `${__ENV.GATEWAY_BASE_URL}/health`
    );

    sleep(1);
}