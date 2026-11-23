my %h=(a=>1); my %c=%h; local $c{a}=2; print "$h{a}\n";
