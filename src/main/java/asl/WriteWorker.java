package main.java.asl;

import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import java.util.Queue;

/**
 * This class is responsible for writing values to memcached and returning responses to the client.
 */
public class WriteWorker implements Runnable {

    private static final Logger log = LogManager.getLogger(WriteWorker.class);

    Integer componentId;

    public WriteWorker(Integer componentId, Queue<Request> writeQueue) {
        this.componentId = componentId;

        // TODO start connections to all memcached servers using MemcachedConnection
        // TODO




        log.info(String.format("Component #%d WriteThread initialised.", componentId));
    }

    @Override
    public void run() {
        // TODO start taking stuff from queue and executing it
    }
}