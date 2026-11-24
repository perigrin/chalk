our $g=1; my $t=0; my $i=0; while ($i++<3) { next if $i==2; $g+=$i; $t+=$g } print "$t $g\n";
