package E; sub new { bless {m => $_[1]}, $_[0] } sub throw { die $_[0]->new($_[1]) } package main; eval { E->throw("t") }; print ref $@, $@->{m}, "\n";
