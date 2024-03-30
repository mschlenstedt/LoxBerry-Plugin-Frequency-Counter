#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <unistd.h>
#include <pthread.h>
#include <pigpio.h>

/*
freq_count_1.c
2014-08-21
Public Domain

Output as JSON in file for LoxBerry plugin added:
2024-02-12 by Michael Schlenstedt

gcc -o freq_count_1 freq_count_1.c -lpigpio -lpthread
$ sudo ./freq_count_1  4 7 8

This program uses the gpioSetAlertFunc function to request
a callback (the same one) for each gpio to be monitored.

EXAMPLES

Monitor gpio 4 (default settings)
sudo ./freq_count_1  4

Monitor gpios 4 and 8 (default settings)
sudo ./freq_count_1  4 8

Monitor gpios 4 and 8, sample rate 2 microseconds
sudo ./freq_count_1  4 8 -s2

Monitor gpios 7 and 8, sample rate 4 microseconds, report every second
sudo ./freq_count_1  7 8 -s4 -r10

Monitor gpios 4,7, 8, 9, 10, 23 24, report five times a second
sudo ./freq_count_1  4 7 8 9 10 23 24 -r2

Monitor gpios 4, 7, 8, and 9, report once a second, sample rate 1us,
generate 2us edges (4us square wave, 250000 highs per second).
sudo ./freq_count_1  4 7 8 9 -r 10 -s 1 -p 2
*/

/*
times with minimal_clk on gpio 4 and 6
sudo ./freq1 4 6 -r10
 7%	0k	0k
 8%	5k	0k
 8%	5k	5k
 9%  10k	5k
 9%  10k  10k
10%  15k  10k
10%  15k  15k
10%  20k  15k
10%  20k  20k
11%  25k  20k
11%  25k  25k
11%  30k  30k
12%  40k  40k
13%  50k  50k
14%  60k  60k
16%  70k  70k
17%  80k  80k
18%  90k  90k
19% 100k 100k

*/

#define MAX_GPIOS 32

#define OPT_P_MIN 1
#define OPT_P_MAX 1000
#define OPT_P_DEF 20

#define OPT_R_MIN 1
#define OPT_R_MAX 300
#define OPT_R_DEF 10

#define OPT_S_MIN 1
#define OPT_S_MAX 10
#define OPT_S_DEF 5

typedef struct
{
	// Sytem tick count when the first edge was recognized
	uint32_t first_tick;
	// Sytem tick count of when the last edge was recognized
	uint32_t last_tick;
	// The count of positive edges
	uint32_t pulse_count;
	// Is set to 1 to one when the values where interpreted to reset the values on the next edge
	int reset;
} gpioData_t;

static volatile gpioData_t edge_gpio_data[MAX_GPIOS];

static uint32_t g_mask;

static int g_num_gpios;
static int g_gpio[MAX_GPIOS];

static int g_opt_p = OPT_P_DEF;
static int g_opt_r = OPT_R_DEF;
static int g_opt_s = OPT_S_DEF;
static int g_opt_t = 0;
static int g_opt_v = 0;

pthread_mutex_t lock;

char *g_opt_f = NULL;
FILE *fp = NULL;

void usage()
{
	fprintf
	(stderr,
		"\n" \
		"Usage: sudo ./freq_count_1 gpio ... [OPTION] ...\n" \
		"	-f filename, export data in json format to filename\n" \
		"	-p value, sets pulses every p micros, %d-%d, TESTING only\n" \
		"	-r value, sets refresh period in deciseconds, %d-%d, default %d\n" \
		"	-s value, sets sampling rate in micros, %d-%d, default %d\n" \
		"	-v verbose output\n" \
		"\nEXAMPLE\n" \
		"sudo ./freq_count_1 4 7 -r2 -s2\n" \
		"Monitor gpios 4 and 7.  Refresh every 0.2 seconds.  Sample rate 2 micros.\n" \
		"\n",
		OPT_P_MIN, OPT_P_MAX,
		OPT_R_MIN, OPT_R_MAX, OPT_R_DEF,
		OPT_S_MIN, OPT_S_MAX, OPT_S_DEF
	);
}

void fatal(int show_usage, char *fmt, ...)
{
	char buf[128];
	va_list ap;

	va_start(ap, fmt);
	vsnprintf(buf, sizeof(buf), fmt, ap);
	va_end(ap);

	fprintf(stderr, "%s\n", buf);

	if (show_usage) usage();

	fflush(stderr);

	exit(EXIT_FAILURE);
}

static int initOpts(int argc, char *argv[])
{
	int i, opt;

	while ((opt = getopt(argc, argv, "p:r:s:f:v")) != -1)
	{
		i = -1;

		switch (opt)
		{
			case 'f':
				g_opt_f = optarg;
				break;

			case 'p':
				i = atoi(optarg);
				if ((i >= OPT_P_MIN) && (i <= OPT_P_MAX))
					g_opt_p = i;
				else fatal(1, "invalid -p option (%d)", i);
				g_opt_t = 1;
				break;

			case 'r':
				i = atoi(optarg);
				if ((i >= OPT_R_MIN) && (i <= OPT_R_MAX))
					g_opt_r = i;
				else fatal(1, "invalid -r option (%d)", i);
				break;

			case 's':
				i = atoi(optarg);
				if ((i >= OPT_S_MIN) && (i <= OPT_S_MAX))
					g_opt_s = i;
				else fatal(1, "invalid -s option (%d)", i);
				break;

			case 'v':
				g_opt_v = 1;
				break;

		  default: /* '?' */
			  usage();
			  exit(-1);
		  }
	 }
	return optind;
}

void edges(int gpio, int level, uint32_t tick)
{
	pthread_mutex_lock(&lock);
	if (edge_gpio_data[gpio].reset)
		memset((void*)&edge_gpio_data[gpio], 0x00, sizeof(gpioData_t));
 
	if (level != PI_TIMEOUT) {
		if (!edge_gpio_data[gpio].first_tick)
			edge_gpio_data[gpio].first_tick = tick;
		edge_gpio_data[gpio].last_tick = tick;
		if (level == 1)
			edge_gpio_data[gpio].pulse_count++;
	}
	pthread_mutex_unlock(&lock);
}

int main(int argc, char *argv[])
{
	if (pthread_mutex_init(&lock, NULL) != 0)
		fatal(1, "Mutex init has failed\n");

	int i, rest, g, wave_id, mode, diff, tally;
	double dbValue;
	gpioPulse_t pulse[2];
	int count[MAX_GPIOS];
	gpioData_t gpio_data;

	for(int iCount = 0; iCount < MAX_GPIOS; iCount++)
		memset((void*)&edge_gpio_data[iCount], 0x00, sizeof(gpioData_t));

	/* command line parameters */

	rest = initOpts(argc, argv);

	/* get the gpios to monitor */

	g_num_gpios = 0;

	for (i=rest; i<argc; i++)
	{
		g = atoi(argv[i]);
		if ((g>=0) && (g<32))
		{
			g_gpio[g_num_gpios++] = g;
			g_mask |= (1<<g);
		}
		else
			fatal(1, "%d is not a valid g_gpio number\n", g);
	}

	if (!g_num_gpios)
		fatal(1, "At least one gpio must be specified");

	printf("Monitoring gpios");
	for (i=0; i<g_num_gpios; i++) printf(" %d", g_gpio[i]);
		printf("\nSample rate %d micros, refresh rate %d deciseconds\n", g_opt_s, g_opt_r);

	gpioCfgClock(g_opt_s, 1, 1);

	if (gpioInitialise()<0)
		return 1;

	gpioWaveClear();

	pulse[0].gpioOn  = g_mask;
	pulse[0].gpioOff = 0;
	pulse[0].usDelay = g_opt_p;

	pulse[1].gpioOn  = 0;
	pulse[1].gpioOff = g_mask;
	pulse[1].usDelay = g_opt_p;

	gpioWaveAddGeneric(2, pulse);

	wave_id = gpioWaveCreate();

	/* monitor g_gpio level changes */

	for (i=0; i<g_num_gpios; i++) {
		gpioSetAlertFunc(g_gpio[i], edges);
		// If no edge is detected for 1000msec, the callback is called with level set to PI_TIMEOUT 
		gpioSetWatchdog(g_gpio[i], 1000);
	}

	mode = PI_INPUT;

	if (g_opt_t)
	{
		gpioWaveTxSend(wave_id, PI_WAVE_MODE_REPEAT);
		mode = PI_OUTPUT;
	}

	if (g_opt_f != NULL)
		printf("Writing data to %s\n", g_opt_f);

	for (i=0; i<g_num_gpios; i++)
		gpioSetMode(g_gpio[i], mode);

	while (1)
	{
		gpioDelay(g_opt_r * 100000);

		// open the file for writing or enable output to stdout
		if (g_opt_f != NULL) {
			fp = fopen(g_opt_f, "w");
			if (fp == NULL) {
				fprintf(stderr, "Error opening the file %s", g_opt_f);
				exit(EXIT_FAILURE);
			}
		} else
			g_opt_v = 1;

		/* start json output */
		if (g_opt_f != NULL)
			fprintf(fp, "{");

		for (i=0; i<g_num_gpios; i++)
		{
			g = g_gpio[i];
			pthread_mutex_lock(&lock);
			gpio_data = edge_gpio_data[g];
			// Set marker to reset the tick values on the next edge
			edge_gpio_data[g].reset = 1;
			pthread_mutex_unlock(&lock);

			diff = gpio_data.last_tick - gpio_data.first_tick;
			if (diff == 0)
				diff = 1;

			tally = gpio_data.pulse_count;
			if (tally && diff > 0)
				dbValue = 1000000.0 * tally / diff;
			else
				dbValue = 0;
		
			 if (diff < 0)
				 diff = 0;
		
			if (g_opt_v == 1)
				printf("g=%d %.2f (%d/%d)\n", g, dbValue, tally, diff);

			/* write to json output */
			if (g_opt_f != NULL) {
				fprintf(fp, "\"gpio%d\": {\"gpio\": %d, \"freq\": %.2f, \"tally\": %d, \"diff\": %d}", g, g, dbValue, tally, diff);
				if (i < g_num_gpios - 1)
					fprintf(fp, ",");
			}
		}

		/* end json output */
		if (g_opt_f != NULL) {
			fprintf(fp, "}\n");
			fclose(fp);
		}

	}

	pthread_mutex_destroy(&lock);
	gpioTerminate();
}

