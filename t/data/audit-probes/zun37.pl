our $g=1; eval { local $g=2; nosuch(); }; print "$g ", ($@ ? "died" : "ok"), "\n";
