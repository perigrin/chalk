our %h=(a=>1); eval { local $h{a} = 2; 1 }; print "$h{a}\n";
