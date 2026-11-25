our $g=1; eval { local $g=2; my $f; $f->(); }; print "$g ", ($@ ? "died" : "ok"), "\n";
