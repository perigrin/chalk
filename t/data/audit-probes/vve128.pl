our %h = (k=>1); sub c { $h{k} = 5; 2 } sub f { "@_" } print f($h{k}, c()), "\n";
