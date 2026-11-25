our $g=0; my $i=0; while ($i++<3) { local $g=$i; last if $i==2 } print "$g$i\n";
