package C; sub new { bless {}, shift } sub repl { $_[0] = 5 } package main; my @o=(C->new); $o[0]->repl; print ref($o[0]) ? "obj" : $o[0], "\n";
