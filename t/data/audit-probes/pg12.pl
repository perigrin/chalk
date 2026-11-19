package Cnt; our $n = 0; sub new { $n++; bless {}, shift } package main; Cnt->new; my $a = $Cnt::n; Cnt->new; print "$a $Cnt::n\n";
