my @f; for my $i (1..3) { push @f, sub { $i } } print join("",map {$_->()} @f),"\n";
