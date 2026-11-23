my %h=(a=>1); my %c=%h; my %d=(%c,x=>1); $c{a}=2; print "$h{a}$d{a}\n";
