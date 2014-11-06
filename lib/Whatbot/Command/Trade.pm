###########################################################################
# Trade.pm
# the whatbot project - http://www.whatbot.org
###########################################################################

package Whatbot::Command::Trade;
use Moose;
BEGIN { extends 'Whatbot::Command' }
use namespace::autoclean;
use Whatbot::Command::Market;
use Number::Format;

our $VERSION = '0.1';

has 'formatter' => (
	is      => 'ro',
	isa     => 'Number::Format',
	default => sub { return Number::Format->new(); }
);

sub register {
	my ( $self ) = @_;
	
	$self->command_priority('Extension');
	$self->require_direct(0);
}

sub help {
	return [
		'Trade is a completely made up stock market simulator, and not a very '
		. 'good one. Use trade to "buy" and "sell" stock based on current '
		. 'market value as provided by the Market command. You are allowed to '
		. 'retain a negative balance, and you get nothing for your troubles.',
		' * buy: Buy shares. (trade buy 5 shares of msft)',
		' * sell: Sell shares. (trade sell 4 shares of msft)',
		' * shares: Get holdings of ticker. (trade shares msft)',
		' * holdings: Show what you have. (trade holdings)',
		' * balance: See current account balance. (trade balance)'
	];
}

sub buy : Command {
	my ( $self, $message, $captures ) = @_;

	my ( $number_shares, $ticker, $price ) = $self->parse_hurf($captures);
	unless ( $number_shares and $ticker) {
		return 'Trade has no idea what that meant. Read help.';
	}
	unless ( $price ) {
		return sprintf( 'Ticker symbol %s was not found.', $ticker );
	}
	if ( $number_shares < 1 or $number_shares !~ /^\d+$/ ) {
		return 'Trade requires a valid, positive, whole number of shares.';
	}

	my $result = $self->model('Trade')->trade( lc( $message->from ), $number_shares, $ticker, $price );
	if ($result) {
		return sprintf(
			'%s, you purchased %s shares of %s at %s, totalling %s minus %0.2f fee. Your balance is %s.',
			$message->from,
			$self->formatter->format_number($number_shares),
			$ticker,
			$self->formatter->format_number($price, 2, 1 ),
			$self->formatter->format_number( $price * $number_shares, 2, 1 ),
			$self->model('Trade')->trade_fee,
			$self->formatter->format_number( $self->model('Trade')->balance( lc( $message->from ) ), 2, 1 )
		);
	}
	return 'Uh.';
}

sub sell : Command {
	my ( $self, $message, $captures ) = @_;

	my ( $number_shares, $ticker, $price ) = $self->parse_hurf($captures);
	unless ( $number_shares and $ticker) {
		return 'Trade has no idea what that meant. Read help.';
	}
	unless ( $price ) {
		return sprintf( 'Ticker symbol %s was not found.', $ticker );
	}
	if ( $number_shares < 1 or $number_shares !~ /^\d+$/ ) {
		return 'Trade requires a valid, positive, whole number of shares.';
	}

	my $user = lc( $message->from );

	# Do we have that many shares
	my $shares = $self->model('Trade')->get_share_count( $user, $ticker );
	if ( $shares < $number_shares ) {
		return sprintf( 
			'%s, you have %s shares of %s. You cannot sell %s shares.',
			$message->from,
			$self->formatter->format_number($shares),
			$ticker,
			$self->formatter->format_number($number_shares),
		);
	}

	# Perform trade
	my $result = $self->model('Trade')->trade( $user, ( $number_shares * -1 ), $ticker, $price );
	if ($result) {
		return sprintf(
			'%s, you sold %s shares of %s at %s, totalling %s minus %0.2f fee. Your balance is %s.',
			$message->from,
			$self->formatter->format_number($number_shares),
			$ticker,
			$price,
			$self->formatter->format_number( $price * $number_shares, 2, 1 ),
			$self->model('Trade')->trade_fee,
			$self->formatter->format_number( $self->model('Trade')->balance( lc( $message->from ) ), 2, 1 )
		);
	}
	return 'Uh.';
}

sub balance : Command {
	my ( $self, $message ) = @_;

	my $balance = $self->model('Trade')->balance( lc( $message->from ) );
	return sprintf( '%s, your balance is %s.', $message->from, $self->formatter->format_number( $balance ), 2, 1 );
}

sub holdings : Command {
	my ( $self, $message ) = @_;

	my $holdings = $self->model('Trade')->holdings( lc( $message->from ) );
	my $assets = 0;
	my @pretty = ( map {
		$assets += $holdings->{$_} * $self->price_for_ticker($_);
		sprintf(
			'%s: %s (%s)',
			$_,
			$self->formatter->format_number( $holdings->{$_} ),
			$self->formatter->format_number( $holdings->{$_} * $self->price_for_ticker($_), 2, 1 )
		)
	} keys %$holdings );
	my $balance = $self->model('Trade')->balance( lc( $message->from ) );
	unshift(
		@pretty,
		sprintf( 'Cash: %s', $self->formatter->format_number( $balance, 2, 1 ) )
	);
	return join( ", ", @pretty ) . '. Total assets: ' . $self->formatter->format_number( $assets + $balance, 2, 1 );
}

sub shares : Command {
	my ( $self, $message, $captures ) = @_;

	my $ticker = uc( $captures->[0] );
	my $shares = $self->model('Trade')->get_share_count( lc( $message->from ), $ticker );
	return sprintf(
		'%s, you have %s share%s of %s, valued at %s.',
		$message->from,
		$self->formatter->format_number($shares),
		( $shares != 1 ? 's' : '' ),
		$ticker,
		$self->formatter->format_number( $shares * $self->price_for_ticker($ticker), 2, 1 )
	);
}

sub parse_hurf {
	my ( $self, $captures ) = @_;

    my $search_text = join( ' ', @$captures );
    return unless ($search_text);

    # Parse message
    my $shares;
    my $ticker;
    if ( $search_text =~ /([\d\.]+) (shares )?(of )?(\w+)/ ) {
    	$shares = $1;
    	$ticker = $4;
    }
    return unless ( $shares and $ticker );

    # Validate ticker
    my $price = $self->price_for_ticker($ticker);

    return ( $shares, $ticker, $price );
}

sub price_for_ticker {
	my ( $self, $ticker ) = @_;

    my $market = Whatbot::Command::Market->new(
		'my_config'      => {},
		'name'           => 'Market'
	);
	my $ticker_data = $market->get_data($ticker);
	if ( $ticker_data and ref($ticker_data) and ref($ticker_data) eq 'HASH' and %$ticker_data) {
		return $ticker_data->{price};
	}
	return;
}

__PACKAGE__->meta->make_immutable;

1;

=pod

=head1 NAME

Whatbot::Command::Trade - A super fake stock market trade "game".

=head1 DESCRIPTION

Whatbot::Command::Trade provides a fake stock market to trade stock. Utilizes
L<Whatbot::Command::Market> to look up quotes, and executes trades with
invisible money. Does not have a limit on how many shares one can purchase,
trades are instant, and one can go into debt.

=head1 LICENSE/COPYRIGHT

Be excellent to each other and party on, dudes.

=cut
