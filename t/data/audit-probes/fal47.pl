my @f; my $i=0; while ($i<3) { my $j=$i; push @f, sub { $j++ }; $i++ } $f[0]->(); print $f[0]->(), $f[1]->(), "\n";
