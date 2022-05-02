using Bogus;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.WebJobs;
using Microsoft.Azure.WebJobs.Extensions.Http;
using Microsoft.Extensions.Logging;
using Newtonsoft.Json;

namespace LoremText
{
	public static class TextGenerator
	{
		[FunctionName(nameof(GenerateText))]
		public static IActionResult GenerateText(
		   [HttpTrigger(
				AuthorizationLevel.Anonymous,
				"get",
				"post",
				Route = "text")] HttpRequest httpRequest,
		   ILogger log,
		   [Queue(
			   queueName: Constants.QUEUE_NAME,
			   Connection = Constants.CONNECTION)] out string msg)
		{
			log.LogInformation($"Generating text.");

			var faker = new Faker("en");

			var lorem = new Bogus.DataSets.Lorem("en");
			var messageString = JsonConvert.SerializeObject(
				lorem.Random.Words(10));

			msg = messageString;

			log.LogInformation($"Sending text: {messageString} to queue: {Constants.QUEUE_NAME}");

			return new OkObjectResult(messageString);
		}
	}
}
