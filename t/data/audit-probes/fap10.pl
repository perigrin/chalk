package C; sub new { bless {}, shift } sub repl { $_[0] = 5 } package main; my %o=(k=>C->new); $o{k}->repl; print ref($o{k}) ? "obj" : $o{k}, "\n";
