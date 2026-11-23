my $n=0; eval { $n=1; my $z=0; my $q=1/$z; $n=2 }; print "$n ", ($@ ? "err":"ok"), "\n";
