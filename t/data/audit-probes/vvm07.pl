our %h = (a=>1); { local %h = (%h, b=>2); print scalar(keys %h) } print scalar(keys %h), "\n";
