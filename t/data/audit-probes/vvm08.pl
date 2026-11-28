our %h = (a=>1); sub f { local %h = (b=>2); join(",", keys %h) } print f(), join(",", keys %h), "\n";
