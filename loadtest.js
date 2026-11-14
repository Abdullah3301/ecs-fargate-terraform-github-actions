import http from 'k6/http';

export const options = {
  vus: 200,
  duration: '10m',
};

// Pass the load balancer address in at runtime:
//   docker run --rm -i -v ${PWD}:/scripts -e ALB_URL=http://your-alb-address grafana/k6 run /scripts/loadtest.js
export default function () {
  http.get(`${__ENV.ALB_URL}/api/`);
}