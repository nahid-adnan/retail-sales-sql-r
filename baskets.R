# Run from the case-study directory with Rscript baskets.R (base R only).
baskets <- read.csv("customer_baskets.csv")
stopifnot(!anyDuplicated(baskets[c("customer_id", "channel")]))
paired <- reshape(baskets[c("customer_id", "channel", "mean_basket_aud")],
                  idvar = "customer_id", timevar = "channel", direction = "wide")
paired <- paired[complete.cases(paired), ]
difference <- paired$mean_basket_aud.Online - paired$mean_basket_aud.Store
stopifnot(length(difference) >= 2L)
set.seed(5840)
bootstrap <- replicate(5000, mean(sample(difference, replace = TRUE)))
interval <- unname(quantile(bootstrap, c(0.025, 0.975)))
results <- data.frame(paired_customers = length(difference),
                      mean_difference_aud = round(mean(difference), 2),
                      lower_95_aud = round(interval[1], 2),
                      upper_95_aud = round(interval[2], 2))
write.csv(results, "basket_interval.csv", row.names = FALSE)
print(results)
