my %h=(a=>1); my %c=%h; $h{a}=2; print "$c{a}\n"; $c{a}=3; print "$h{a}\n";
