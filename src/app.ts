import Fastify from "fastify";
import { logger } from "./lib/logger";

const app = Fastify({ logger: false });

app.get("/", async (_req, reply) => {
  return reply.send({ status: "ok", uptime: process.uptime() });
});

app.get("/health", async (_req, reply) => {
  return reply.send({ status: "ok" });
});

export default {
  listen(port: number, callback: (err: Error | null) => void) {
    app
      .listen({ port, host: "0.0.0.0" })
      .then(() => {
        logger.info({ port }, "Fastify server listening");
        callback(null);
      })
      .catch((err) => {
        callback(err);
      });
  },
};
