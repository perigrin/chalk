use feature 'try'; no warnings; my $n=0; for my $i (1..3) { try { next if $i==2; $n+=$i } catch ($e) { } } print "$n\n";
