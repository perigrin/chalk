my %h=(a=>1); my %c=%h; sub w1 { $_[0]{a}=2 } w1(\%c); print "$h{a}\n";
