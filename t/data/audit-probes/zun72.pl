package C; our $g=1; sub new { bless {}, shift } sub m { local $g=2; die "x\n" } package main; eval { C->new->m }; print "$C::g\n";
