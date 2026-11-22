our $g=1; eval { local $g = 2; require No::Such::Mod; }; print "$g\n";
