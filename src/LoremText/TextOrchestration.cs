using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using Microsoft.Azure.WebJobs;
using Microsoft.Azure.WebJobs.Extensions.DurableTask;
using Microsoft.Extensions.Logging;

namespace LoremText
{
	public static class TextOrchestration
	{
		[FunctionName(nameof(TextProcessor))]
		public static async Task TextProcessor(
			[QueueTrigger(
				queueName:Constants.QUEUE_NAME,
			   	Connection = Constants.CONNECTION)]
			string myQueueItem,
			[DurableClient] IDurableOrchestrationClient starter,
			ILogger log)
		{
			//Artificial delay to allow increase in queue depth
			await Task.Delay(15 * 1000);

			string instanceId = await starter.StartNewAsync(nameof(GetWordsWithoutVowels), null, myQueueItem);

			log.LogInformation($"Started orchestration with ID = '{instanceId}'.");
		}

		[FunctionName(nameof(GetWordsWithoutVowels))]
		public static async Task<string> GetWordsWithoutVowels(
			[OrchestrationTrigger] IDurableOrchestrationContext context)
		{
			var outputs = new List<Task<string>>();
			var msg = context.GetInput<string>();

			var words = msg.Split(" ");

			foreach (var word in words)
			{
				outputs.Add(context.CallActivityAsync<string>(nameof(RemoveVowels), word));
			}

			var result = await Task.WhenAll(outputs);

			return string.Join(" ", result.ToList());

		}

		[FunctionName(nameof(RemoveVowels))]
		public static string RemoveVowels([ActivityTrigger] string word, ILogger log)
		{
			var wordWithoutVowels = Regex.Replace(word, "[aeiouy]", "", RegexOptions.IgnoreCase);
			log.LogInformation($"Removed vowels, result: {wordWithoutVowels}.");
			return $"{wordWithoutVowels}";
		}
	}
}