our $g=1; eval { local $g=2; my $o; $o->m; }; print "$g ", ($@ ? "died" : "ok"), "\n";
