package main.java.asl;

import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import java.util.Queue;

/**
 * This class is responsible for reading values from memcached and returning responses to the client.
 */
public class ReadWorker implements Runnable {

    Integer componentId;
    Integer threadId;

    private static final Logger log = LogManager.getLogger(ReadWorker.class);

    public ReadWorker(Integer componentId, Integer threadId, Queue<Request> readQueue) {
        this.componentId = componentId;
        this.threadId = threadId;

        // TODO start connection to our memcached server using MemcachedConnection
        // TODO


        log.info(String.format("%s Component #%d ReadWorker #%d initialised.", getName(), componentId, threadId));
    }

    @Override
    public void run() {
        // TODO start taking stuff from queue and executing it
    }

    public String getName() {
        return String.format("c%dr%d", componentId, threadId);
    }
}
