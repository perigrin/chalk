package E; sub new { bless {}, shift } package F; our @ISA = ("E"); package main; eval { die F->new }; print $@->isa("E") ? "isa" : "no", "\n";
