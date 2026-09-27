.libPaths("C:/Users/chigo/R/library")

library(readr)
library(dplyr)
library(lubridate)
library(janitor)
library(skimr)
library(ggplot2)
library(tidyr)

# --- Step 1: Load data ---
shipments <- read_csv(
  "data/SCMS_Delivery_History_Dataset_20150929.csv",
  locale = locale(encoding = "windows-1252"),
  show_col_types = FALSE
) %>%
  clean_names()

cat("Dimensions (rows, cols):\n")
print(dim(shipments))

cat("\nColumn names:\n")
print(names(shipments))

# --- Step 2: Structure / data types ---
cat("\n--- glimpse() ---\n")
glimpse(shipments)

# --- Step 3: Missing values + non-numeric placeholders ---
cat("\n--- Missing values per column ---\n")
print(colSums(is.na(shipments)))

cat("\n--- Non-numeric values in weight_kilograms ---\n")
print(
  shipments %>%
    filter(is.na(suppressWarnings(as.numeric(weight_kilograms)))) %>%
    count(weight_kilograms, sort = TRUE)
)

cat("\n--- Non-numeric values in freight_cost_usd ---\n")
print(
  shipments %>%
    filter(is.na(suppressWarnings(as.numeric(freight_cost_usd)))) %>%
    count(freight_cost_usd, sort = TRUE)
)

cat("\n--- Placeholder text in scheduled_delivery_date ---\n")
print(
  shipments %>%
    filter(is.na(suppressWarnings(dmy(scheduled_delivery_date)))) %>%
    count(scheduled_delivery_date, sort = TRUE)
)

# --- Step 4: Parse dates, compute delivery delay ---
shipments <- shipments %>%
  mutate(
    scheduled_delivery_date = dmy(scheduled_delivery_date),
    delivered_to_client_date = dmy(delivered_to_client_date),
    delivery_recorded_date = dmy(delivery_recorded_date),
    delay_days = as.numeric(delivered_to_client_date - scheduled_delivery_date)
  )

cat("\n--- Delivery delay (days): summary ---\n")
print(summary(shipments$delay_days))

cat("\n--- Delay distribution: on-time vs early vs late ---\n")
delay_status <- shipments %>%
  mutate(delay_bucket = case_when(
    delay_days < 0  ~ "Early",
    delay_days == 0 ~ "On time",
    delay_days > 0  ~ "Late"
  )) %>%
  count(delay_bucket, sort = TRUE) %>%
  mutate(pct = round(100 * n / sum(n), 1))
print(delay_status)

p0 <- ggplot(delay_status, aes(x = reorder(delay_bucket, -n), y = n, fill = delay_bucket)) +
  geom_col(show.legend = FALSE) +
  geom_text(aes(label = paste0(pct, "%")), vjust = -0.4, size = 3.5) +
  scale_fill_manual(values = c("On time" = "#639922", "Early" = "#378ADD", "Late" = "#E24B4A")) +
  labs(title = "Delivery status: on-time vs early vs late", x = NULL, y = "Shipment count") +
  theme_minimal(base_size = 12)
ggsave("plots/05_delay_status_breakdown.png", p0, width = 6, height = 4, dpi = 150)
cat("Saved plots/05_delay_status_breakdown.png\n")

# --- Step 5: Investigate extreme delay outliers ---
cat("\n--- 10 most extreme early/late shipments ---\n")
print(
  shipments %>%
    select(id, country, shipment_mode, scheduled_delivery_date,
           delivered_to_client_date, delay_days) %>%
    arrange(delay_days) %>%
    slice(c(1:5, (n()-4):n()))
)

cat("\n--- How many shipments beyond +/-90 days? ---\n")
print(
  shipments %>%
    filter(abs(delay_days) > 90) %>%
    count(shipment_mode, sort = TRUE)
)

# --- Step 6: Categorical breakdowns ---
cat("\n--- Shipment mode ---\n")
mode_volume <- shipments %>% count(shipment_mode, sort = TRUE) %>% mutate(pct = round(100*n/sum(n),1))
print(mode_volume)

cat("\n--- Top 10 countries by shipment count ---\n")
country_volume <- shipments %>% count(country, sort = TRUE) %>% slice_head(n = 10)
print(country_volume)

cat("\n--- Product group ---\n")
product_volume <- shipments %>% count(product_group, sort = TRUE) %>% mutate(pct = round(100*n/sum(n),1))
print(product_volume)

p5 <- ggplot(mode_volume, aes(x = reorder(shipment_mode, n), y = n)) +
  geom_col(fill = "#7F77DD") +
  geom_text(aes(label = paste0(format(n, big.mark = ","), " (", pct, "%)")), hjust = -0.05, size = 3) +
  coord_flip(clip = "off") +
  labs(title = "Shipment volume by mode", x = NULL, y = "Number of shipments") +
  theme_minimal(base_size = 12) +
  theme(plot.margin = margin(5, 55, 5, 5))
ggsave("plots/07_shipment_volume_by_mode.png", p5, width = 7, height = 4, dpi = 150)
cat("Saved plots/07_shipment_volume_by_mode.png\n")

p6 <- ggplot(country_volume, aes(x = reorder(country, n), y = n)) +
  geom_col(fill = "#5DCAA5") +
  geom_text(aes(label = format(n, big.mark = ",")), hjust = -0.15, size = 3) +
  coord_flip(clip = "off") +
  labs(title = "Top 10 countries by shipment volume", x = NULL, y = "Number of shipments") +
  theme_minimal(base_size = 12) +
  theme(plot.margin = margin(5, 30, 5, 5))
ggsave("plots/08_top_countries_by_volume.png", p6, width = 7, height = 5, dpi = 150)
cat("Saved plots/08_top_countries_by_volume.png\n")

p7 <- ggplot(product_volume, aes(x = reorder(product_group, n), y = n)) +
  geom_col(fill = "#F0997B") +
  geom_text(aes(label = paste0(format(n, big.mark = ","), " (", pct, "%)")), hjust = -0.05, size = 3) +
  coord_flip(clip = "off") +
  labs(title = "Shipment volume by product group", x = NULL, y = "Number of shipments") +
  theme_minimal(base_size = 12) +
  theme(plot.margin = margin(5, 55, 5, 5))
ggsave("plots/09_product_group_distribution.png", p7, width = 7, height = 4, dpi = 150)
cat("Saved plots/09_product_group_distribution.png\n")

# --- Step 7: Freight cost (numeric subset only) by shipment mode ---
shipments <- shipments %>%
  mutate(freight_cost_numeric = suppressWarnings(as.numeric(freight_cost_usd)))

cat("\n--- Freight cost: how many rows are usable numeric values? ---\n")
cat(sum(!is.na(shipments$freight_cost_numeric)), "of", nrow(shipments), "\n")

# DECISION: freight_cost_usd mixes real numbers with categorical statuses
# ("Freight Included in Commodity Cost", "Invoiced Separately", cross-reference
# notes). We exclude the non-numeric rows from freight $ analysis rather than
# guessing a fill value -- they aren't missing data, they're a different kind
# of answer, and averaging over an assumed fill would misstate the real cost.
freight_usability <- tibble(
  status = c("Usable (numeric $)", "Categorical status / cross-reference"),
  n = c(sum(!is.na(shipments$freight_cost_numeric)),
        sum(is.na(shipments$freight_cost_numeric)))
) %>% mutate(pct = round(100 * n / sum(n), 1))

p9 <- ggplot(freight_usability, aes(x = status, y = n, fill = status)) +
  geom_col(show.legend = FALSE) +
  geom_text(aes(label = paste0(format(n, big.mark=","), " (", pct, "%)")), vjust = -0.4, size = 3.5) +
  scale_fill_manual(values = c("Usable (numeric $)" = "#639922",
                                "Categorical status / cross-reference" = "#888780")) +
  labs(title = "Decision: why freight-cost analysis uses only 60% of rows",
       subtitle = "The other 40% are legitimate categorical statuses, not missing data -- excluded rather than guessed",
       x = NULL, y = "Shipment count") +
  theme_minimal(base_size = 12) +
  theme(plot.subtitle = element_text(size = 9))
ggsave("plots/11_freight_usability_decision.png", p9, width = 7, height = 4.5, dpi = 150)
cat("Saved plots/11_freight_usability_decision.png\n")

cat("\n--- Avg freight cost (USD) by shipment mode, numeric subset ---\n")
print(
  shipments %>%
    filter(!is.na(freight_cost_numeric)) %>%
    group_by(shipment_mode) %>%
    summarise(n = n(), avg_freight_usd = round(mean(freight_cost_numeric), 0),
              median_freight_usd = round(median(freight_cost_numeric), 0)) %>%
    arrange(desc(avg_freight_usd))
)

cat("\n--- Median delay (days) by shipment mode ---\n")
mode_summary <- shipments %>%
  group_by(shipment_mode) %>%
  summarise(n = n(), median_delay = median(delay_days, na.rm = TRUE),
            pct_late = round(100 * mean(delay_days > 0, na.rm = TRUE), 1),
            avg_freight_usd = round(mean(freight_cost_numeric, na.rm = TRUE), 0)) %>%
  arrange(desc(pct_late))
print(mode_summary)

# --- Step 8: Visualize delay rate and freight cost by shipment mode ---
p1 <- ggplot(mode_summary, aes(x = reorder(shipment_mode, pct_late), y = pct_late)) +
  geom_col(fill = "#2c7fb8") +
  geom_text(aes(label = paste0(pct_late, "%")), hjust = -0.15) +
  coord_flip() +
  labs(title = "% of shipments delivered late, by shipment mode",
       x = NULL, y = "% late") +
  theme_minimal(base_size = 12)
ggsave("plots/01_pct_late_by_mode.png", p1, width = 7, height = 4, dpi = 150)
cat("\nSaved plots/01_pct_late_by_mode.png\n")

p2 <- ggplot(mode_summary, aes(x = reorder(shipment_mode, avg_freight_usd), y = avg_freight_usd)) +
  geom_col(fill = "#d95f0e") +
  geom_text(aes(label = paste0("$", format(avg_freight_usd, big.mark = ","))), hjust = -0.1) +
  coord_flip() +
  labs(title = "Average freight cost (USD), by shipment mode",
       x = NULL, y = "Avg freight cost (USD)") +
  theme_minimal(base_size = 12)
ggsave("plots/02_avg_freight_by_mode.png", p2, width = 7, height = 4, dpi = 150)
cat("Saved plots/02_avg_freight_by_mode.png\n")

# --- Step 9: Which countries drive the late-delivery rate? ---
country_summary <- shipments %>%
  filter(!is.na(delay_days)) %>%
  group_by(country) %>%
  summarise(n = n(),
            pct_late = round(100 * mean(delay_days > 0), 1),
            median_delay = median(delay_days)) %>%
  filter(n >= 30) %>%          # drop low-volume countries so the rate isn't noise
  arrange(desc(pct_late))

cat("\n--- Late-delivery rate by country (n >= 30 shipments), worst 15 ---\n")
print(country_summary %>% slice_head(n = 15))

cat("\n--- Best 5 (lowest % late), for contrast ---\n")
print(country_summary %>% slice_tail(n = 5))

cat("\n--- Countries excluded for low volume (n < 30) ---\n")
low_vol <- shipments %>% filter(!is.na(delay_days)) %>% count(country) %>% filter(n < 30)
cat(nrow(low_vol), "countries excluded,", sum(low_vol$n), "shipments\n")

p3 <- ggplot(country_summary %>% slice_head(n = 15),
             aes(x = reorder(country, pct_late), y = pct_late)) +
  geom_col(fill = "#e34a33") +
  geom_text(aes(label = paste0(pct_late, "% (n=", n, ")")), hjust = -0.05, size = 3) +
  coord_flip() +
  labs(title = "Top 15 countries by % of shipments delivered late",
       subtitle = "Countries with at least 30 shipments",
       x = NULL, y = "% late") +
  theme_minimal(base_size = 12) +
  theme(plot.margin = margin(5, 40, 5, 5))
ggsave("plots/03_pct_late_by_country.png", p3, width = 8, height = 6, dpi = 150)
cat("\nSaved plots/03_pct_late_by_country.png\n")

# Cross-check: is the country effect actually a shipment-mode-mix effect?
cat("\n--- Shipment mode mix for the 5 worst-late countries ---\n")
worst5 <- country_summary %>% slice_head(n = 5) %>% pull(country)
mode_mix <- shipments %>%
  filter(country %in% worst5) %>%
  count(country, shipment_mode) %>%
  group_by(country) %>%
  mutate(pct = round(100 * n / sum(n), 1)) %>%
  arrange(country, desc(n))
print(mode_mix)

p8 <- ggplot(mode_mix, aes(x = factor(country, levels = worst5), y = pct, fill = shipment_mode)) +
  geom_col(position = "stack") +
  geom_text(aes(label = ifelse(pct >= 5, paste0(pct, "%"), "")),
            position = position_stack(vjust = 0.5), size = 3, color = "white") +
  scale_fill_manual(values = c("Air" = "#378ADD", "Truck" = "#eb6834", "Air Charter" = "#1baf7a",
                                "Ocean" = "#eda100", "NA" = "#888780")) +
  labs(title = "Shipment mode mix: the 5 worst-late countries",
       subtitle = "Burundi/Congo DRC are ~100% Air (a country bottleneck) vs. Mozambique/Zambia/Zimbabwe (Truck-heavy, a mode-mix effect)",
       x = NULL, y = "% of country's shipments", fill = "Mode") +
  theme_minimal(base_size = 12) +
  theme(plot.title = element_text(size = 12), plot.subtitle = element_text(size = 9))
ggsave("plots/10_country_mode_mix.png", p8, width = 8, height = 5, dpi = 150)
cat("Saved plots/10_country_mode_mix.png\n")

# --- Step 10: Investigate the year-offset anomaly ---

# 10a. Is there a distinct cluster near -365 days, separate from the main spread?
cat("\n--- Histogram of delay_days near the +/-1 year mark ---\n")
p4 <- ggplot(shipments %>% filter(!is.na(delay_days)), aes(x = delay_days)) +
  geom_histogram(binwidth = 15, fill = "#31a354", color = "white") +
  labs(title = "Distribution of delivery delay (days)",
       subtitle = "Look for a secondary cluster away from zero",
       x = "Delay (days): negative = early, positive = late", y = "Shipment count") +
  theme_minimal(base_size = 12)
ggsave("plots/04_delay_histogram.png", p4, width = 8, height = 5, dpi = 150)
cat("Saved plots/04_delay_histogram.png\n")

# 10b. Isolate shipments near a whole year off (330-400 days either direction)
year_offset <- shipments %>%
  filter(abs(delay_days) >= 330 & abs(delay_days) <= 400) %>%
  mutate(
    sched_month_day = format(scheduled_delivery_date, "%m-%d"),
    deliv_month_day  = format(delivered_to_client_date, "%m-%d"),
    same_month_day   = sched_month_day == deliv_month_day,
    year_diff        = year(scheduled_delivery_date) - year(delivered_to_client_date)
  )

cat("\n--- How many shipments sit ~1 year off? ---\n")
cat(nrow(year_offset), "of", nrow(shipments), "rows (",
    round(100 * nrow(year_offset) / nrow(shipments), 2), "% )\n")

cat("\n--- Do scheduled and delivered share the same month/day (just year differs)? ---\n")
print(year_offset %>% count(same_month_day, year_diff))

cat("\n--- Detail: all ~1-year-off shipments ---\n")
print(
  year_offset %>%
    select(id, country, shipment_mode, project_code, po_so_number,
           scheduled_delivery_date, delivered_to_client_date, delay_days)
)

# 10c. Do these rows share a PO/SO number or project code (single data-entry event)?
cat("\n--- Shared PO/SO numbers among the ~1-year-off rows ---\n")
print(year_offset %>% count(po_so_number, sort = TRUE))

cat("\n--- Shared project codes among the ~1-year-off rows ---\n")
print(year_offset %>% count(project_code, sort = TRUE))

# 10d. Quantify how much these 4 rows actually move the aggregate stats
cat("\n--- Impact of the 4 outlier rows on mean/median delay ---\n")
clean_delay <- shipments$delay_days[abs(shipments$delay_days) < 330]
cat("Mean delay,   all rows (n=", sum(!is.na(shipments$delay_days)), "): ",
    round(mean(shipments$delay_days, na.rm = TRUE), 2), " days\n", sep = "")
cat("Mean delay,   excluding the 4 outliers (n=", length(clean_delay), "): ",
    round(mean(clean_delay, na.rm = TRUE), 2), " days\n", sep = "")
cat("Median delay, all rows: ", median(shipments$delay_days, na.rm = TRUE),
    " | excluding outliers: ", median(clean_delay, na.rm = TRUE), "\n", sep = "")

# DECISION: keep the 4 outlier rows in the main analysis rather than filtering
# them out. They don't share a PO/SO number, project code, or country (so
# they're not one systemic event), and removing them barely moves the mean
# (-6.02 -> -5.88 days) and doesn't touch the median at all -- not worth the
# complexity of a separate "cleaned" dataset for a 0.04%-of-rows edge case.
before_after <- tibble(
  version = factor(c("Before: all 10,324 rows", "After: excluding the 4 outliers"),
                    levels = c("Before: all 10,324 rows", "After: excluding the 4 outliers")),
  mean_delay = c(mean(shipments$delay_days, na.rm = TRUE), mean(clean_delay, na.rm = TRUE))
)

p10 <- ggplot(before_after, aes(x = version, y = mean_delay)) +
  geom_col(fill = "#7F77DD", width = 0.5) +
  geom_text(aes(label = round(mean_delay, 2)), vjust = -0.4, size = 4) +
  labs(title = "Decision: keep the 4 year-offset outliers in the dataset",
       subtitle = "Excluding them moves the mean by 0.14 days -- not worth a separate cleaned dataset for 0.04% of rows",
       x = NULL, y = "Mean delay (days)") +
  theme_minimal(base_size = 12) +
  theme(plot.subtitle = element_text(size = 9))
ggsave("plots/12_outlier_decision.png", p10, width = 7, height = 4.5, dpi = 150)
cat("Saved plots/12_outlier_decision.png\n")

# --- Step 12: Statistical rigor -- are the country differences even real? ---
# The country %late ranking (Step 9) never asked whether the gaps between
# countries are statistically meaningful or just sampling noise from small n.
# A Wilson-style CI (via prop.test) answers that directly.
country_stats <- shipments %>%
  filter(!is.na(delay_days)) %>%
  group_by(country) %>%
  summarise(n = n(), late_n = sum(delay_days > 0)) %>%
  filter(n >= 30) %>%
  arrange(desc(late_n / n)) %>%
  slice_head(n = 15)

ci_bounds <- Map(function(x, n) prop.test(x, n)$conf.int, country_stats$late_n, country_stats$n)
country_stats <- country_stats %>%
  mutate(
    pct_late = round(100 * late_n / n, 1),
    ci_low = round(100 * sapply(ci_bounds, `[`, 1), 1),
    ci_high = round(100 * sapply(ci_bounds, `[`, 2), 1)
  )

cat("\n--- % late by country with 95% confidence intervals ---\n")
print(country_stats %>% select(country, n, pct_late, ci_low, ci_high))

p11 <- ggplot(country_stats, aes(x = reorder(country, pct_late), y = pct_late)) +
  geom_pointrange(aes(ymin = ci_low, ymax = ci_high), color = "#378ADD", size = 0.5) +
  coord_flip() +
  labs(title = "% late by country, with 95% confidence intervals",
       subtitle = "Overlapping intervals mean we can't statistically tell those countries apart -- only Burundi and Congo DRC clearly stand out",
       x = NULL, y = "% late (with 95% CI)") +
  theme_minimal(base_size = 12) +
  theme(plot.subtitle = element_text(size = 9))
ggsave("plots/13_country_pct_late_with_ci.png", p11, width = 8, height = 5.5, dpi = 150)
cat("Saved plots/13_country_pct_late_with_ci.png\n")

# --- Step 13: Two fields that turned out to matter a lot in the Python model
# but were never explored here -- fulfill_via and vendor_inco_term ---
cat("\n--- % late by fulfill_via ---\n")
fulfill_summary <- shipments %>%
  group_by(fulfill_via) %>%
  summarise(n = n(), pct_late = round(100 * mean(delay_days > 0, na.rm = TRUE), 1)) %>%
  arrange(desc(pct_late))
print(fulfill_summary)

cat("\n--- % late by vendor_inco_term (n >= 30) ---\n")
inco_summary <- shipments %>%
  group_by(vendor_inco_term) %>%
  summarise(n = n(), pct_late = round(100 * mean(delay_days > 0, na.rm = TRUE), 1)) %>%
  filter(n >= 30) %>%
  arrange(desc(pct_late))
print(inco_summary)

p12 <- ggplot(fulfill_summary, aes(x = reorder(fulfill_via, pct_late), y = pct_late)) +
  geom_col(fill = "#6250d6") +
  geom_text(aes(label = paste0(pct_late, "% (n=", n, ")")), hjust = -0.05, size = 3.5) +
  coord_flip(clip = "off") +
  labs(title = "% late by fulfill_via", x = NULL, y = "% late") +
  theme_minimal(base_size = 12) +
  theme(plot.margin = margin(5, 60, 5, 5))
ggsave("plots/14_fulfill_via_pct_late.png", p12, width = 7, height = 3.5, dpi = 150)
cat("\nSaved plots/14_fulfill_via_pct_late.png\n")

p13 <- ggplot(inco_summary, aes(x = reorder(vendor_inco_term, pct_late), y = pct_late)) +
  geom_col(fill = "#e87ba4") +
  geom_text(aes(label = paste0(pct_late, "% (n=", n, ")")), hjust = -0.05, size = 3.5) +
  coord_flip(clip = "off") +
  labs(title = "% late by vendor Incoterm (n >= 30)", x = NULL, y = "% late") +
  theme_minimal(base_size = 12) +
  theme(plot.margin = margin(5, 60, 5, 5))
ggsave("plots/15_vendor_inco_term_pct_late.png", p13, width = 7, height = 4, dpi = 150)
cat("Saved plots/15_vendor_inco_term_pct_late.png\n")

# --- Step 14: Bivariate numeric exploration -- do order size/pricing differ
# between on-time and late shipments? (Foreshadows the Python model's finding
# that pack_price/quantity outrank shipment_mode as predictors.) ---
numeric_compare <- shipments %>%
  filter(!is.na(freight_cost_numeric)) %>%
  mutate(is_late_label = ifelse(delay_days > 0, "Late", "On-time/Early")) %>%
  select(is_late_label, freight_cost_numeric, pack_price, unit_price, line_item_quantity) %>%
  pivot_longer(cols = -is_late_label, names_to = "metric", values_to = "value") %>%
  filter(value > 0)   # log scale needs strictly positive values

cat("\n--- Median of each numeric feature, on-time/early vs late ---\n")
print(
  numeric_compare %>%
    group_by(metric, is_late_label) %>%
    summarise(median_value = round(median(value), 2), .groups = "drop")
)

p14 <- ggplot(numeric_compare, aes(x = is_late_label, y = value, fill = is_late_label)) +
  geom_boxplot(show.legend = FALSE, outlier.alpha = 0.15) +
  scale_y_log10() +
  facet_wrap(~metric, scales = "free_y", ncol = 2) +
  scale_fill_manual(values = c("Late" = "#E24B4A", "On-time/Early" = "#639922")) +
  labs(title = "Do order size and pricing differ between on-time and late shipments?",
       subtitle = "Log scale (heavy right-skew). This is what the Python model later confirmed as the stronger signal, ahead of shipment mode.",
       x = NULL, y = "Value (log scale)") +
  theme_minimal(base_size = 11) +
  theme(plot.subtitle = element_text(size = 8.5))
ggsave("plots/16_numeric_features_by_late_status.png", p14, width = 8, height = 6, dpi = 150)
cat("\nSaved plots/16_numeric_features_by_late_status.png\n")

# --- Step 15: Time trend -- has delivery performance improved or worsened
# over the dataset's 2006-2015 span? Never looked at until now. ---
year_trend <- shipments %>%
  filter(!is.na(delay_days)) %>%
  mutate(sched_year = year(scheduled_delivery_date)) %>%
  group_by(sched_year) %>%
  summarise(n = n(), pct_late = round(100 * mean(delay_days > 0), 1)) %>%
  filter(n >= 30)

cat("\n--- % late by year (n >= 30) ---\n")
print(year_trend)

p15 <- ggplot(year_trend, aes(x = sched_year, y = pct_late)) +
  geom_line(color = "#378ADD", linewidth = 1) +
  geom_point(color = "#378ADD", size = 2.5) +
  geom_text(aes(label = paste0(pct_late, "%")), vjust = -1.2, size = 3.5) +
  scale_x_continuous(breaks = year_trend$sched_year) +
  labs(title = "% late by scheduled year",
       subtitle = "Years with fewer than 30 shipments excluded",
       x = NULL, y = "% late") +
  theme_minimal(base_size = 12) +
  theme(plot.subtitle = element_text(size = 9))
ggsave("plots/17_pct_late_trend_by_year.png", p15, width = 8, height = 4.5, dpi = 150)
cat("Saved plots/17_pct_late_trend_by_year.png\n")

# --- Step 16: Export cleaned dataset for the SQL layer ---
shipments_clean <- shipments %>%
  mutate(
    shipment_mode = na_if(shipment_mode, "N/A"),
    scheduled_delivery_date = as.character(scheduled_delivery_date),
    delivered_to_client_date = as.character(delivered_to_client_date),
    delivery_recorded_date = as.character(delivery_recorded_date)
  ) %>%
  select(id, project_code, country, managed_by, fulfill_via, vendor_inco_term,
         shipment_mode, scheduled_delivery_date, delivered_to_client_date,
         delivery_recorded_date, delay_days, product_group, sub_classification,
         vendor, brand, line_item_quantity, line_item_value, pack_price, unit_price,
         manufacturing_site, first_line_designation, freight_cost_numeric)

write_csv(shipments_clean, "data/shipments_clean.csv")
cat("\nSaved data/shipments_clean.csv:", nrow(shipments_clean), "rows,", ncol(shipments_clean), "cols\n")
