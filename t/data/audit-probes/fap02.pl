package C; sub new { bless {}, shift } sub nul { $_[0] = undef } package main; my $o=C->new; $o->nul; print defined $o ? "d" : "u", "\n";
