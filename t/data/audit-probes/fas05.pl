our %h=(a=>1); sub rd { $h{a} } sub t { local $h{a}=5; rd() } print t(), rd(), "\n";
