our %h = (a=>1,b=>2); sub f { local @h{qw(a b)} = (8,9); "$h{a}$h{b}" } print f(), "$h{a}$h{b}\n";
