sub f { $_[0]{k} = 1 } my $h; f($h); print ref($h) || "undef", "\n";
