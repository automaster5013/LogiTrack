package io.logitrack.stream;

import org.springframework.stereotype.Component;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;
import java.io.IOException;
import java.util.concurrent.CopyOnWriteArrayList;

@Component
public class DeliveryStream {
    private final CopyOnWriteArrayList<SseEmitter> clients=new CopyOnWriteArrayList<>();
    public SseEmitter subscribe(){
        var e=new SseEmitter(0L); clients.add(e); e.onCompletion(()->clients.remove(e)); e.onTimeout(()->clients.remove(e));
        try{e.send(SseEmitter.event().name("connected").data("ok"));}catch(IOException ex){clients.remove(e);}
        return e;
    }
    public void publish(Object value){for(var e:clients){try{e.send(SseEmitter.event().name("delivery-update").data(value));}catch(IOException ex){clients.remove(e);}}}
}

