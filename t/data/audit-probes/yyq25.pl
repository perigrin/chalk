my $u; print defined(length($u)) ? "d" : "u", defined(length(undef)) ? "d" : "u", length($u) // "U", "\n";
