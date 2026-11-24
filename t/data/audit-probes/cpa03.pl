our %h=(a=>1); my %c=%h; $c{a}=2; $h{b}=3; print join(",", sort keys %h), " $h{a} ", join(",", sort keys %c), " $c{a}\n";
