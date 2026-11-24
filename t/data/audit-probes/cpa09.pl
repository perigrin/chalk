my %h=(a=>1); my %c; for my $i (1..2) { %c=%h; $c{a}=$i*10; } print "$h{a} $c{a}\n";
