our %h = (a=>1,b=>2); { local $h{a} = 8; print "$h{a}$h{b}" } print "$h{a}$h{b}\n";
