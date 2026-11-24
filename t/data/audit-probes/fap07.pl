package C; sub new { bless {}, shift } sub kill { undef $_[0] } package main; my $o=C->new; $o->kill; print defined $o ?1:0, "\n";
