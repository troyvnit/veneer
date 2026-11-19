import 'package:flutter/widgets.dart';

import '../app_icons.dart';

/// The kinds of place Explore filters by, in the glass segment bar's order.
enum Mood {
  all('All', AppIcons.globeHemisphereWest),
  beach('Beaches', AppIcons.umbrellaSimple),
  city('Cities', AppIcons.buildings),
  mountains('Mountains', AppIcons.mountains),
  culture('Culture', AppIcons.bank),
  desert('Deserts', AppIcons.cactus);

  const Mood(this.label, this.icon);

  final String label;
  final IconData icon;
}

class Place {
  const Place({
    required this.id,
    required this.name,
    required this.country,
    required this.mood,
    required this.image,
    this.gallery = const [],
    required this.rating,
    required this.reviews,
    required this.blurb,
    required this.bestTime,
    required this.flight,
    required this.budget,
    required this.tips,
  });

  final String id;
  final String name;
  final String country;
  final Mood mood;
  final String image;
  final List<String> gallery;
  final double rating;
  final String reviews;
  final String blurb;
  final String bestTime;
  final String flight;
  final int budget;
  final List<String> tips;

  String get title => '$name, $country';
}

Place placeById(String id) => places.firstWhere((p) => p.id == id, orElse: () => places.first);

const places = [
  Place(
    id: 'kyoto',
    name: 'Kyoto',
    country: 'Japan',
    mood: Mood.culture,
    image: 'assets/images/kyoto.jpg',
    gallery: ['assets/images/kyoto_2.jpg', 'assets/images/tokyo.jpg'],
    rating: 4.9,
    reviews: '2.1k',
    blurb:
        'Temples in the hills, lantern-lit lanes in Gion and gardens that change with every season. Come in '
        'early April for the cherry blossom, or in November when the maples turn.',
    bestTime: 'Mar – May',
    flight: '11h 40m',
    budget: 140,
    tips: [
      'Reach Fushimi Inari before 7am to have the gates to yourself.',
      'A one-day bus pass covers most temples; the subway is quicker across town.',
      'Book a ryokan with dinner at least once — kaiseki is the point.',
    ],
  ),
  Place(
    id: 'santorini',
    name: 'Santorini',
    country: 'Greece',
    mood: Mood.beach,
    image: 'assets/images/santorini.jpg',
    gallery: ['assets/images/santorini_2.jpg'],
    rating: 4.8,
    reviews: '3.4k',
    blurb:
        'Whitewashed villages on the rim of a flooded volcano. Swim from black-sand beaches, walk the caldera '
        'path from Fira to Oia, and stay up for the most famous sunset in the Aegean.',
    bestTime: 'May – Oct',
    flight: '4h 05m',
    budget: 190,
    tips: [
      'Walk Fira to Oia (10 km) in the morning, before the heat.',
      'Watch the sunset from Imerovigli: same view as Oia, a tenth of the crowd.',
      'Ferries beat flights between the islands in summer.',
    ],
  ),
  Place(
    id: 'patagonia',
    name: 'El Chaltén',
    country: 'Argentina',
    mood: Mood.mountains,
    image: 'assets/images/patagonia.jpg',
    rating: 4.9,
    reviews: '860',
    blurb:
        'The trekking capital of Patagonia, at the foot of Fitz Roy. Trails leave from the edge of town to '
        'glacier lakes and granite spires; the weather changes every hour.',
    bestTime: 'Nov – Mar',
    flight: '16h 20m',
    budget: 95,
    tips: [
      'Start Laguna de los Tres at 3am for sunrise on Fitz Roy.',
      'Pack layers: four seasons in a day is not an exaggeration.',
      'There is one ATM in town. Bring cash.',
    ],
  ),
  Place(
    id: 'lisbon',
    name: 'Lisbon',
    country: 'Portugal',
    mood: Mood.city,
    image: 'assets/images/lisbon.jpg',
    gallery: ['assets/images/lisbon_2.jpg'],
    rating: 4.7,
    reviews: '5.2k',
    blurb:
        'Seven hills, yellow trams and tiled façades above the Tagus. Eat pastéis de nata in Belém, get lost in '
        'Alfama, and catch the last light from a miradouro.',
    bestTime: 'Apr – Jun',
    flight: '2h 35m',
    budget: 110,
    tips: [
      'Ride tram 28 early in the morning; by noon it is standing room only.',
      'Most miradouros have a kiosk bar — sunset with a drink costs €3.',
      'Sintra is 40 minutes by train. Go on a weekday.',
    ],
  ),
  Place(
    id: 'maldives',
    name: 'Maldives',
    country: 'Indian Ocean',
    mood: Mood.beach,
    image: 'assets/images/maldives.jpg',
    gallery: ['assets/images/maldives_2.jpg'],
    rating: 4.9,
    reviews: '1.8k',
    blurb:
        'A thousand coral islands strung across the equator. Snorkel with manta rays, sleep over the lagoon and '
        'measure the day by the tide.',
    bestTime: 'Nov – Apr',
    flight: '9h 50m',
    budget: 420,
    tips: [
      'Local islands have guesthouses at a fraction of resort prices.',
      'Seaplane transfers only fly in daylight; plan your arrival time.',
      'Hanifaru Bay is the place for manta rays from June to November.',
    ],
  ),
  Place(
    id: 'iceland',
    name: 'Skógafoss',
    country: 'Iceland',
    mood: Mood.mountains,
    image: 'assets/images/iceland.jpg',
    gallery: ['assets/images/iceland_2.jpg'],
    rating: 4.8,
    reviews: '2.6k',
    blurb:
        'A 60-metre curtain of water on the south coast, and the start of the Fimmvörðuháls trail over the '
        'pass between two glaciers.',
    bestTime: 'Jun – Sep',
    flight: '3h 10m',
    budget: 230,
    tips: [
      'Climb the 527 steps to the top and follow the river for twenty more waterfalls.',
      'Come in the evening: the midnight sun lights the spray.',
      'Fill your bottle from any stream; the water is cleaner than bottled.',
    ],
  ),
  Place(
    id: 'positano',
    name: 'Positano',
    country: 'Italy',
    mood: Mood.beach,
    image: 'assets/images/positano.jpg',
    gallery: ['assets/images/positano_2.jpg'],
    rating: 4.7,
    reviews: '4.0k',
    blurb:
        'Houses in every shade of terracotta tumble down to the sea on the Amalfi Coast. Take a boat to the '
        'grottoes, walk the Path of the Gods, and eat lemon everything.',
    bestTime: 'May – Sep',
    flight: '2h 20m',
    budget: 230,
    tips: [
      'The ferry from Amalfi is faster and prettier than the coast road.',
      'Walk the Path of the Gods from Bomerano down to Nocelle.',
      'Book beach loungers the day before in August.',
    ],
  ),
  Place(
    id: 'tokyo',
    name: 'Tokyo',
    country: 'Japan',
    mood: Mood.city,
    image: 'assets/images/tokyo.jpg',
    rating: 4.8,
    reviews: '6.7k',
    blurb:
        'Neon alleys in Shinjuku, quiet shrines between skyscrapers and the best food city on earth. Every '
        'neighbourhood feels like a different city.',
    bestTime: 'Mar – May',
    flight: '12h 05m',
    budget: 160,
    tips: [
      'A Suica card in your phone wallet covers trains, buses and convenience stores.',
      'Omoide Yokocho is busiest at 8pm; go at 6 for a seat.',
      'Day trip to Kamakura for the Great Buddha and the coast.',
    ],
  ),
  Place(
    id: 'marrakech',
    name: 'Marrakech',
    country: 'Morocco',
    mood: Mood.culture,
    image: 'assets/images/marrakech.jpg',
    rating: 4.6,
    reviews: '3.1k',
    blurb:
        'Spice stalls, lantern sellers and riads hidden behind plain doors. The medina is a maze — getting lost '
        'is the plan.',
    bestTime: 'Mar – May',
    flight: '3h 25m',
    budget: 80,
    tips: [
      'Jemaa el-Fnaa comes alive after sunset; eat at the food stalls.',
      'Agree on a price before any taxi ride.',
      'Le Jardin Secret is a calm hour away from the souks.',
    ],
  ),
  Place(
    id: 'moraine',
    name: 'Moraine Lake',
    country: 'Canada',
    mood: Mood.mountains,
    image: 'assets/images/moraine.jpg',
    rating: 4.9,
    reviews: '2.9k',
    blurb:
        'Glacier-fed water the colour of a gemstone under the Valley of the Ten Peaks. Paddle at sunrise, then '
        'hike to Larch Valley.',
    bestTime: 'Jun – Sep',
    flight: '10h 15m',
    budget: 210,
    tips: [
      'The road is closed to cars: book the Parks Canada shuttle in advance.',
      'Canoes rent from 8:30am; the lake is glassiest before then.',
      'In late September the larches turn gold.',
    ],
  ),
  Place(
    id: 'bali',
    name: 'Ubud',
    country: 'Bali',
    mood: Mood.culture,
    image: 'assets/images/bali.jpg',
    rating: 4.7,
    reviews: '4.4k',
    blurb:
        'Rice terraces, jungle temples and yoga shalas in Bali’s green heart. Rent a scooter, follow the ridge '
        'walks and stay for the dance at the palace.',
    bestTime: 'Apr – Oct',
    flight: '16h 45m',
    budget: 70,
    tips: [
      'Tegallalang terraces are best before 8am.',
      'Campuhan Ridge Walk is free and flat.',
      'Cover shoulders and knees for temples; sarongs are lent at the gate.',
    ],
  ),
  Place(
    id: 'sahara',
    name: 'Merzouga',
    country: 'Morocco',
    mood: Mood.desert,
    image: 'assets/images/sahara.jpg',
    rating: 4.8,
    reviews: '1.2k',
    blurb:
        'The dunes of Erg Chebbi rise 150 metres from the desert floor. Ride out at sunset, sleep in a camp and '
        'climb for the sunrise.',
    bestTime: 'Oct – Apr',
    flight: '3h 25m',
    budget: 90,
    tips: [
      'Nights are cold even in spring; bring a warm layer.',
      'The road from Marrakech takes two days — stop in the Dades Gorge.',
      'Sandboarding is better than it sounds.',
    ],
  ),
];

class Trip {
  const Trip({
    required this.id,
    required this.name,
    required this.dates,
    required this.cover,
    required this.stops,
    required this.travelers,
    required this.days,
    this.past = false,
  });

  final String id;
  final String name;
  final String dates;
  final String cover;
  final List<String> stops;
  final List<String> travelers;
  final List<TripDay> days;
  final bool past;
}

class TripDay {
  const TripDay(this.title, this.place, this.items);

  final String title;
  final String place;
  final List<(String, String)> items;
}

const trips = [
  Trip(
    id: 'japan',
    name: 'Japan in spring',
    dates: 'Mar 28 – Apr 9',
    cover: 'assets/images/kyoto.jpg',
    stops: ['Tokyo', 'Kyoto'],
    travelers: ['Maya', 'Leo', 'Sam'],
    days: [
      TripDay('Day 1', 'Tokyo', [
        ('16:40', 'Land at Haneda, Suica on the phone'),
        ('19:00', 'Dinner in Omoide Yokocho'),
      ]),
      TripDay('Day 2', 'Tokyo', [
        ('09:00', 'Meiji Shrine and Harajuku'),
        ('14:00', 'teamLab Planets'),
        ('20:00', 'Shibuya Sky at night'),
      ]),
      TripDay('Day 5', 'Kyoto', [
        ('06:30', 'Fushimi Inari before the crowds'),
        ('11:00', 'Nishiki Market lunch'),
        ('17:30', 'Gion at dusk'),
      ]),
      TripDay('Day 6', 'Kyoto', [
        ('08:00', 'Arashiyama bamboo grove'),
        ('13:00', 'Kinkaku-ji'),
        ('19:00', 'Kaiseki dinner at the ryokan'),
      ]),
    ],
  ),
  Trip(
    id: 'portugal',
    name: 'Lisbon to the Sahara',
    dates: 'May 14 – May 26',
    cover: 'assets/images/lisbon_2.jpg',
    stops: ['Lisbon', 'Marrakech', 'Merzouga'],
    travelers: ['Maya', 'Ana'],
    days: [
      TripDay('Day 1', 'Lisbon', [
        ('10:00', 'Tram 28 to Alfama'),
        ('18:30', 'Sunset at Miradouro da Senhora do Monte'),
      ]),
      TripDay('Day 4', 'Marrakech', [('11:00', 'Riad check-in, mint tea'), ('19:00', 'Food stalls on Jemaa el-Fnaa')]),
      TripDay('Day 7', 'Merzouga', [('17:00', 'Camel ride into Erg Chebbi'), ('05:45', 'Sunrise from the big dune')]),
    ],
  ),
  Trip(
    id: 'iceland',
    name: 'Iceland ring road',
    dates: 'Aug 2 – Aug 12',
    cover: 'assets/images/iceland_2.jpg',
    stops: ['Reykjavík', 'Skógafoss', 'Höfn'],
    travelers: ['Leo'],
    days: [
      TripDay('Day 1', 'Reykjavík', [('14:00', 'Pick up the camper'), ('21:00', 'Sky Lagoon')]),
      TripDay('Day 2', 'South coast', [('10:00', 'Seljalandsfoss'), ('15:00', 'Skógafoss and the trail above')]),
    ],
  ),
  Trip(
    id: 'amalfi',
    name: 'Amalfi summer',
    dates: 'Jul 2026',
    cover: 'assets/images/positano_2.jpg',
    stops: ['Positano', 'Amalfi'],
    travelers: ['Maya', 'Sam'],
    past: true,
    days: [
      TripDay('Day 1', 'Positano', [('12:00', 'Lunch on the beach'), ('17:00', 'Boat to the grottoes')]),
    ],
  ),
  Trip(
    id: 'maldives',
    name: 'Maldives',
    dates: 'Dec 2025',
    cover: 'assets/images/maldives_2.jpg',
    stops: ['Malé', 'Baa Atoll'],
    travelers: ['Maya'],
    past: true,
    days: [
      TripDay('Day 1', 'Baa Atoll', [('09:00', 'Seaplane from Malé'), ('15:00', 'Snorkel the house reef')]),
    ],
  ),
];

/// Colours for the people on a trip, by first letter.
const travelerColors = {'M': Color(0xFFE8912D), 'L': Color(0xFF2EB67D), 'S': Color(0xFF36C5F0), 'A': Color(0xFF8E6CEF)};

/// The app's accent: a sunset coral.
const accent = Color(0xFFFF5F45);
