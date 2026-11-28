package C; our $cnt = 0; sub new { $cnt++; bless {id => $cnt}, shift } package main; my @o = map { C->new } 1..3; print $o[2]{id}, $C::cnt, "\n";
