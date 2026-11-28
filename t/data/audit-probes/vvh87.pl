sub DESTROY {} my $x = 1; eval { $x++; die bless {}, "main" }; print ref($@), "$x\n";
