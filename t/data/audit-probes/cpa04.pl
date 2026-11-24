my %h=(a=>1); our %c=%h; $c{a}=2; $h{a}=7; print "$h{a} $c{a}\n";
