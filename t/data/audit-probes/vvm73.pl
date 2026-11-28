our %h = (k=>1); sub f :lvalue { $h{k} } { local $h{k} = 7; f() = 5; print $h{k} } print $h{k}, "\n";
