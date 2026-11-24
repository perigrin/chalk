my %h=(a=>1); for my $i (1..3) { my %c=%h; $c{a}+=$i; $h{a}++ if $i==2; print "$c{a} " } print "$h{a}\n";
