our $g="ab"; sub t { $g =~ tr/a/z/ } print $g . t() . $g, "\n";
