namespace DriveOp.Api.Entities
{
    public class NumberSequence
    {
        public Guid MunicipalityId { get; set; }
        public Municipality Municipality { get; set; } = null!;

        public string SequenceName { get; set; } = null!;
        public string PeriodKey { get; set; } = null!;
        public int LastValue { get; set; }
    }
}
