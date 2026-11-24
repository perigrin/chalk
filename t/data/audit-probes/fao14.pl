package C; sub new { bless {}, shift } sub repl { $_[0] = "gone" } package main; my $o=C->new; $o->repl; print ref($o) ? "obj" : $o, "\n";
