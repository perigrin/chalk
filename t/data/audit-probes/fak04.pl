my @f; my $i=0; while ($i<2) { push @f, sub { $i }; $i++ } print $f[0]->(), $f[1]->(), "\n";
