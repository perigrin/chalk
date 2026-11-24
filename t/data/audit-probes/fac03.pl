my %h=(a=>1); my @o; for my $i (1..3) { my %c=%h; $c{a}+=$i; push @o,$c{a} } print "@o $h{a}\n";
